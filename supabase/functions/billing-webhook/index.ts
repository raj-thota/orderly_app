// billing-webhook — deployed with --no-verify-jwt.
// Auth = gateway signature verification only.
// Uses service role: writes only to subscriptions + billing_events.

import { createClient } from "jsr:@supabase/supabase-js@2";

const RAZORPAY_WEBHOOK_SECRET = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";

const CORS = { "Access-Control-Allow-Origin": "*" };

function plainJson(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return plainJson({ error: "method_not_allowed" }, 405);

  const rawBody = await req.arrayBuffer();
  const bodyText = new TextDecoder().decode(rawBody);

  const stripeSignature = req.headers.get("stripe-signature");
  const razorpaySignature = req.headers.get("x-razorpay-signature");

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  if (stripeSignature) {
    return await _handleStripe(supabase, rawBody, bodyText, stripeSignature);
  } else if (razorpaySignature) {
    return await _handleRazorpay(supabase, bodyText, razorpaySignature);
  }

  return plainJson({ error: "unknown_gateway" }, 400);
});

// ---------------------------------------------------------------------------
// Stripe
// ---------------------------------------------------------------------------

async function _handleStripe(
  supabase: ReturnType<typeof createClient>,
  rawBody: ArrayBuffer,
  bodyText: string,
  signature: string,
): Promise<Response> {
  if (!await _verifyStripeSignature(rawBody, signature, STRIPE_WEBHOOK_SECRET)) {
    console.error("stripe signature invalid");
    return plainJson({ error: "invalid_signature" }, 400);
  }

  let event: { id: string; type: string; data: { object: Record<string, unknown> } };
  try {
    event = JSON.parse(bodyText);
  } catch {
    return plainJson({ error: "invalid_json" }, 400);
  }

  const obj = event.data.object;
  const eventId = event.id;
  const eventType = event.type;

  // Idempotency: skip if already processed.
  const { error: dupErr } = await supabase.from("billing_events").insert({
    id: eventId,
    gateway: "stripe",
    type: eventType,
    payload: obj,
  });
  if (dupErr) {
    if (dupErr.code === "23505") return plainJson({ ok: true, duplicate: true });
    console.error("billing_events insert:", dupErr.message);
    return plainJson({ error: "db_error" }, 500);
  }

  const customerId = obj["customer"] as string | undefined;
  if (!customerId) return plainJson({ ok: true, skipped: "no_customer" });

  // Look up subscription by gateway_customer_id.
  const { data: sub } = await supabase
    .from("subscriptions")
    .select("id, user_id")
    .eq("gateway_customer_id", customerId)
    .maybeSingle();

  if (!sub) {
    console.warn("stripe event: no subscription for customer", customerId);
    return plainJson({ ok: true, skipped: "no_subscription" });
  }

  const stripeSub = obj["subscription"] as Record<string, unknown> | undefined;
  const currentPeriodEnd = stripeSub?.["current_period_end"]
    ? new Date(Number(stripeSub["current_period_end"]) * 1000).toISOString()
    : undefined;

  const update = _stripeEventToUpdate(eventType, currentPeriodEnd);
  if (update) {
    const { error: upErr } = await supabase
      .from("subscriptions")
      .update({ ...update, updated_at: new Date().toISOString() })
      .eq("id", sub.id);
    if (upErr) {
      console.error("subscription update:", upErr.message);
      return plainJson({ error: "update_failed" }, 500);
    }
  }

  return plainJson({ ok: true });
}

function _stripeEventToUpdate(
  type: string,
  currentPeriodEnd?: string,
): Record<string, unknown> | null {
  switch (type) {
    case "checkout.session.completed":
    case "customer.subscription.updated":
      return { status: "active", current_period_end: currentPeriodEnd };
    case "invoice.payment_succeeded":
      return { status: "active", current_period_end: currentPeriodEnd };
    case "invoice.payment_failed":
      return { status: "past_due" };
    case "customer.subscription.deleted":
      return { status: "cancelled" };
    default:
      return null;
  }
}

async function _verifyStripeSignature(
  rawBody: ArrayBuffer,
  header: string,
  secret: string,
): Promise<boolean> {
  if (!secret) return false;
  // Header format: t=<timestamp>,v1=<sig>,...
  const parts = Object.fromEntries(
    header.split(",").map((p) => p.split("=") as [string, string]),
  );
  const timestamp = parts["t"];
  const expected = parts["v1"];
  if (!timestamp || !expected) return false;

  const payload = `${timestamp}.${new TextDecoder().decode(rawBody)}`;
  const keyBytes = new TextEncoder().encode(secret);
  const msgBytes = new TextEncoder().encode(payload);
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, msgBytes);
  const computed = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return computed === expected;
}

// ---------------------------------------------------------------------------
// Razorpay
// ---------------------------------------------------------------------------

async function _handleRazorpay(
  supabase: ReturnType<typeof createClient>,
  bodyText: string,
  signature: string,
): Promise<Response> {
  if (!await _verifyRazorpaySignature(bodyText, signature, RAZORPAY_WEBHOOK_SECRET)) {
    console.error("razorpay signature invalid");
    return plainJson({ error: "invalid_signature" }, 400);
  }

  let event: { event: string; payload: Record<string, unknown>; account_id?: string };
  try {
    event = JSON.parse(bodyText);
  } catch {
    return plainJson({ error: "invalid_json" }, 400);
  }

  const eventType = event.event;
  const payload = event.payload;

  // Razorpay doesn't provide stable event IDs; derive from subscription + event type.
  const subPayload = payload["subscription"] as { entity?: Record<string, unknown> } | undefined;
  const rzpSubId = subPayload?.entity?.["id"] as string | undefined;
  const eventId = rzpSubId ? `rzp_${rzpSubId}_${eventType}` : `rzp_${Date.now()}_${eventType}`;

  // Idempotency.
  const { error: dupErr } = await supabase.from("billing_events").insert({
    id: eventId,
    gateway: "razorpay",
    type: eventType,
    payload: payload,
  });
  if (dupErr) {
    if (dupErr.code === "23505") return plainJson({ ok: true, duplicate: true });
    console.error("billing_events insert:", dupErr.message);
    return plainJson({ error: "db_error" }, 500);
  }

  if (!rzpSubId) return plainJson({ ok: true, skipped: "no_subscription_id" });

  const { data: sub } = await supabase
    .from("subscriptions")
    .select("id, user_id")
    .eq("gateway_subscription_id", rzpSubId)
    .maybeSingle();

  if (!sub) {
    console.warn("razorpay event: no subscription for", rzpSubId);
    return plainJson({ ok: true, skipped: "no_subscription" });
  }

  const entity = subPayload?.entity ?? {};
  const currentPeriodEnd = entity["current_end"]
    ? new Date(Number(entity["current_end"]) * 1000).toISOString()
    : undefined;

  const update = _razorpayEventToUpdate(eventType, currentPeriodEnd);
  if (update) {
    const { error: upErr } = await supabase
      .from("subscriptions")
      .update({ ...update, updated_at: new Date().toISOString() })
      .eq("id", sub.id);
    if (upErr) {
      console.error("subscription update:", upErr.message);
      return plainJson({ error: "update_failed" }, 500);
    }
  }

  return plainJson({ ok: true });
}

function _razorpayEventToUpdate(
  type: string,
  currentPeriodEnd?: string,
): Record<string, unknown> | null {
  switch (type) {
    case "subscription.activated":
      return { status: "active", current_period_end: currentPeriodEnd };
    case "subscription.charged":
      return { status: "active", current_period_end: currentPeriodEnd };
    case "subscription.payment_failed":
      return { status: "past_due" };
    case "subscription.cancelled":
      return { status: "cancelled" };
    case "subscription.expired":
      return { status: "expired" };
    default:
      return null;
  }
}

async function _verifyRazorpaySignature(
  body: string,
  signature: string,
  secret: string,
): Promise<boolean> {
  if (!secret) return false;
  const keyBytes = new TextEncoder().encode(secret);
  const msgBytes = new TextEncoder().encode(body);
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, msgBytes);
  const computed = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return computed === signature;
}
