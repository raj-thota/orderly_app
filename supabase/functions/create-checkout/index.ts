import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

// Plan amounts are defined server-side only — never trust client for pricing.
const RAZORPAY_PLAN_ID = Deno.env.get("RAZORPAY_PLAN_ID") ?? "";
const STRIPE_PRICE_ID = Deno.env.get("STRIPE_PRICE_ID") ?? "";

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

  let body: { gateway?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const gateway = body.gateway;
  if (gateway !== "razorpay" && gateway !== "stripe") {
    return json({ error: "invalid_gateway" }, 400);
  }

  // Fetch or create the subscription row (ensure_trial creates one if missing).
  const { data: sub, error: subErr } = await supabase
    .from("subscriptions")
    .select("id, gateway_customer_id")
    .eq("user_id", userId)
    .maybeSingle();

  if (subErr) return json({ error: "subscription_lookup_failed" }, 500);

  try {
    if (gateway === "razorpay") {
      return await _razorpayCheckout(supabase, userId, userEmail, sub?.id, sub?.gateway_customer_id);
    } else {
      return await _stripeCheckout(supabase, userId, userEmail, sub?.id, sub?.gateway_customer_id);
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : "unknown";
    console.error("create-checkout error:", msg);
    return json({ error: "checkout_failed" }, 500);
  }
});

async function _razorpayCheckout(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  email: string,
  subId: string | undefined,
  existingCustomerId: string | undefined,
): Promise<Response> {
  const keyId = Deno.env.get("RAZORPAY_KEY_ID")!;
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET")!;
  const authB64 = btoa(`${keyId}:${keySecret}`);
  const headers = {
    Authorization: `Basic ${authB64}`,
    "Content-Type": "application/json",
  };

  // Create or reuse Razorpay customer.
  let customerId = existingCustomerId;
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
      plan_id: RAZORPAY_PLAN_ID,
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

  // Persist gateway IDs on our subscription row (pending state — webhook will activate).
  if (subId) {
    await supabase.from("subscriptions").update({
      gateway: "razorpay",
      gateway_customer_id: customerId,
      gateway_subscription_id: rzpSub.id,
    }).eq("id", subId);
  }

  return json({ short_url: rzpSub.short_url });
}

async function _stripeCheckout(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  email: string,
  subId: string | undefined,
  existingCustomerId: string | undefined,
): Promise<Response> {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!;
  const headers = {
    Authorization: `Bearer ${stripeKey}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };

  // Create or reuse Stripe customer.
  let customerId = existingCustomerId;
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
    "line_items[0][price]": STRIPE_PRICE_ID,
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

  // Persist gateway IDs pending webhook confirmation.
  if (subId) {
    await supabase.from("subscriptions").update({
      gateway: "stripe",
      gateway_customer_id: customerId,
    }).eq("id", subId);
  }

  return json({ checkout_url: sess.url });
}
