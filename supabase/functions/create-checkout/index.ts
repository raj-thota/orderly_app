import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

// Plan amounts are defined server-side only — never trust client for pricing.
// Single purchasable plan: Closr Pro ₹499/mo (all AI). The planned WhatsApp
// tier (₹999) is shown as coming-soon in the app and is not sellable yet.
const RAZORPAY_PLAN_ID = Deno.env.get("RAZORPAY_PLAN_ID") ?? ""; // Pro ₹499
const STRIPE_PRICE_ID = Deno.env.get("STRIPE_PRICE_ID") ?? ""; // Pro ₹499

const VALID_PLANS = new Set(["pro_monthly"]);

// createClient's generics don't unify across call sites under deno check;
// the helpers below only need the untyped query interface.
// deno-lint-ignore no-explicit-any
type AdminClient = any;

function razorpayPlanId(_plan: string): string {
  return RAZORPAY_PLAN_ID;
}

function stripePriceId(_plan: string): string {
  return STRIPE_PRICE_ID;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) return json({ error: "unauthorized" }, 401);
  const userId = userData.user.id;
  const userEmail = userData.user.email ?? "";

  let body: { gateway?: string; plan?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const gateway = body.gateway;
  if (gateway !== "razorpay" && gateway !== "stripe") {
    return json({ error: "invalid_gateway" }, 400);
  }

  // Default to Pro if the client sends an unknown/absent plan.
  const plan = VALID_PLANS.has(body.plan ?? "") ? body.plan! : "pro_monthly";

  // Subscription writes below must use the service role: authenticated has
  // SELECT only on subscriptions (webhook is the writer of record), so a
  // user-scoped update would fail and the gateway IDs would never be linked
  // — the webhook then can't activate the paid subscription.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: sub, error: subErr } = await admin
    .from("subscriptions")
    .select("id, plan, status, gateway, gateway_customer_id, gateway_subscription_id")
    .eq("user_id", userId)
    .maybeSingle();

  if (subErr) return json({ error: "subscription_lookup_failed" }, 500);

  // An active subscriber re-buying the same plan would end up double-billed.
  if (sub?.status === "active" && sub.plan === plan) {
    return json({ error: "already_subscribed" }, 409);
  }

  // Stripe is not live yet (the app only offers Razorpay). Refuse rather
  // than run a path that can't cancel a prior Stripe subscription — the
  // webhook never stores Stripe subscription ids, so a retry could stack
  // two live subscriptions with no way to cancel the old one here.
  if (gateway === "stripe" && !Deno.env.get("STRIPE_SECRET_KEY")) {
    return json({ error: "gateway_unavailable" }, 400);
  }

  try {
    if (gateway === "razorpay") {
      return await _razorpayCheckout(admin, userId, userEmail, sub, plan);
    } else {
      return await _stripeCheckout(admin, userId, userEmail, sub, plan);
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : "unknown";
    console.error("create-checkout error:", msg);
    return json({ error: "checkout_failed" }, 500);
  }
});

type SubRow = {
  id: string;
  plan: string;
  status: string;
  gateway: string | null;
  gateway_customer_id: string | null;
  gateway_subscription_id: string | null;
} | null;

async function _razorpayCheckout(
  admin: AdminClient,
  userId: string,
  email: string,
  sub: SubRow,
  plan: string,
): Promise<Response> {
  const keyId = Deno.env.get("RAZORPAY_KEY_ID")!;
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET")!;
  const authB64 = btoa(`${keyId}:${keySecret}`);
  const headers = {
    Authorization: `Basic ${authB64}`,
    "Content-Type": "application/json",
  };

  if (!RAZORPAY_PLAN_ID) {
    console.error("RAZORPAY_PLAN_ID is not configured");
    return json({ error: "checkout_failed" }, 500);
  }

  // Retry after an abandoned checkout (or future plan switch): cancel the
  // previous Razorpay subscription first. Any cancel failure aborts — even
  // past_due/trialing subs are live at the gateway and can still charge, so
  // proceeding could double-bill. A 400 for an already-terminal sub is fine
  // to abort on too: the retry can simply happen again.
  const oldRzpSubId = sub?.gateway === "razorpay" ? sub.gateway_subscription_id : null;
  if (oldRzpSubId) {
    const cancelRes = await fetch(
      `https://api.razorpay.com/v1/subscriptions/${oldRzpSubId}/cancel`,
      { method: "POST", headers, body: JSON.stringify({ cancel_at_cycle_end: 0 }) },
    );
    // Razorpay returns 400 for subs already in a terminal state (cancelled/
    // expired/completed) — treat that as already-cancelled, abort otherwise.
    if (!cancelRes.ok) {
      const errBody = await cancelRes.text();
      const alreadyTerminal = cancelRes.status === 400 &&
        /not cancellable|already cancelled|completed|expired/i.test(errBody);
      if (!alreadyTerminal) {
        console.error("razorpay cancel-before-switch failed:", errBody);
        return json({ error: "plan_change_failed" }, 500);
      }
    }
  }

  // Create or reuse Razorpay customer.
  let customerId = sub?.gateway === "razorpay" ? sub.gateway_customer_id : null;
  if (!customerId) {
    const custRes = await fetch("https://api.razorpay.com/v1/customers", {
      method: "POST",
      headers,
      body: JSON.stringify({ email, fail_existing: 0 }),
    });
    if (!custRes.ok) {
      const errBody = await custRes.text();
      throw new Error(`razorpay_customer_create: ${errBody}`);
    }
    const cust = await custRes.json() as { id: string };
    customerId = cust.id;
  }

  // Create subscription on Razorpay.
  const rzpSubRes = await fetch("https://api.razorpay.com/v1/subscriptions", {
    method: "POST",
    headers,
    body: JSON.stringify({
      plan_id: razorpayPlanId(plan),
      customer_id: customerId,
      total_count: 120,   // 10 years max; cancellable anytime
      quantity: 1,
    }),
  });
  if (!rzpSubRes.ok) {
    const errBody = await rzpSubRes.text();
    throw new Error(`razorpay_subscription_create: ${errBody}`);
  }
  const rzpSub = await rzpSubRes.json() as { id: string; short_url: string };

  // Persist gateway IDs (webhook activates on payment). If this write fails
  // the webhook could never match the subscription, so the checkout URL must
  // not be handed out — cancel the just-created gateway sub and error.
  const persistErr = await _persistGatewayIds(admin, userId, sub?.id, {
    plan,
    gateway: "razorpay",
    gateway_customer_id: customerId,
    gateway_subscription_id: rzpSub.id,
  });
  if (persistErr) {
    console.error("persist after razorpay create failed:", persistErr);
    await fetch(`https://api.razorpay.com/v1/subscriptions/${rzpSub.id}/cancel`, {
      method: "POST",
      headers,
      body: JSON.stringify({ cancel_at_cycle_end: 0 }),
    }).catch(() => {});
    return json({ error: "checkout_failed" }, 500);
  }

  return json({ short_url: rzpSub.short_url });
}

// Updates the user's subscription row, or inserts a placeholder row when
// none exists (possible if checkout is reached before ensure_trial ran).
// Returns an error message on failure, null on success.
async function _persistGatewayIds(
  admin: AdminClient,
  userId: string,
  subId: string | undefined,
  fields: Record<string, unknown>,
): Promise<string | null> {
  if (subId) {
    // The service role bypasses RLS, so scope by user_id as well — a foreign
    // subId can never redirect the write to another user's row.
    const { error } = await admin
      .from("subscriptions")
      .update(fields)
      .eq("id", subId)
      .eq("user_id", userId);
    return error ? error.message : null;
  }
  const { error } = await admin
    .from("subscriptions")
    .insert({ user_id: userId, status: "expired", ...fields });
  return error ? error.message : null;
}

async function _stripeCheckout(
  admin: AdminClient,
  userId: string,
  email: string,
  sub: SubRow,
  plan: string,
): Promise<Response> {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!;
  const headers = {
    Authorization: `Bearer ${stripeKey}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };

  // Create or reuse Stripe customer.
  let customerId = sub?.gateway === "stripe" ? sub.gateway_customer_id : null;
  if (!customerId) {
    const params = new URLSearchParams({ email, "metadata[user_id]": userId });
    const custRes = await fetch("https://api.stripe.com/v1/customers", {
      method: "POST",
      headers,
      body: params.toString(),
    });
    if (!custRes.ok) {
      const errBody = await custRes.text();
      throw new Error(`stripe_customer_create: ${errBody}`);
    }
    const cust = await custRes.json() as { id: string };
    customerId = cust.id;
  }

  const appUrl = Deno.env.get("APP_URL") ?? "https://closr.app";

  // Create Stripe Checkout Session.
  const params = new URLSearchParams({
    customer: customerId,
    "line_items[0][price]": stripePriceId(plan),
    "line_items[0][quantity]": "1",
    mode: "subscription",
    success_url: `${appUrl}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${appUrl}/billing/cancel`,
    "metadata[user_id]": userId,
  });
  const sessRes = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers,
    body: params.toString(),
  });
  if (!sessRes.ok) {
    const errBody = await sessRes.text();
    throw new Error(`stripe_checkout_create: ${errBody}`);
  }
  const sess = await sessRes.json() as { id: string; url: string };

  // Persist gateway IDs pending webhook confirmation. The webhook matches
  // Stripe events by customer id, so this write failing means the payment
  // could never activate — fail the checkout instead.
  const persistErr = await _persistGatewayIds(admin, userId, sub?.id, {
    plan,
    gateway: "stripe",
    gateway_customer_id: customerId,
  });
  if (persistErr) {
    console.error("persist after stripe session failed:", persistErr);
    return json({ error: "checkout_failed" }, 500);
  }

  return json({ checkout_url: sess.url });
}
