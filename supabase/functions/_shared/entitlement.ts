// Server-side AI entitlement gate. Client-side gating is UX only — every AI
// edge function must call this after auth, before doing paid work.
//
// AI access = Pro trial still running, or a paid Pro subscription. Starter
// (₹499) is the non-AI tier: active-but-starter is denied here even though
// the app itself treats the account as subscribed.

import { json } from "./cors.ts";

const AI_PLANS = new Set(["pro_monthly"]);

// Minimal structural view of the query we run — supabase-js generic
// parameters don't unify across modules, so the concrete client type
// can't be named here without tripping deno check.
interface EntitlementClient {
  from(table: string): {
    select(columns: string): {
      maybeSingle(): PromiseLike<{
        // deno-lint-ignore no-explicit-any
        data: any;
        error: { message: string } | null;
      }>;
    };
  };
}

/**
 * Returns null when the caller may use AI, or a ready-to-return 402 Response
 * when they may not. Uses the user-scoped client: RLS restricts the read to
 * the caller's own subscription row, so no service role is needed.
 */
export async function requireAiAccess(
  supabase: EntitlementClient,
): Promise<Response | null> {
  const { data: sub, error } = await supabase
    .from("subscriptions")
    .select("plan, status, trial_end")
    .maybeSingle();

  // Fail closed: an unreadable subscription state must not grant free AI.
  if (error) {
    console.error("entitlement lookup failed:", error.message);
    return json({ error: "subscription_required" }, 402);
  }
  if (!sub) return json({ error: "subscription_required" }, 402);

  const plan = String(sub.plan ?? "");
  const status = String(sub.status ?? "");

  if (status === "active" && AI_PLANS.has(plan)) return null;

  // Trials are always created on an AI plan (ensure_trial), but check the
  // plan anyway so a future non-AI tier's trial can't slip through.
  if (status === "trialing" && AI_PLANS.has(plan)) {
    const trialEnd = sub.trial_end ? Date.parse(String(sub.trial_end)) : NaN;
    if (!Number.isNaN(trialEnd) && trialEnd > Date.now()) return null;
  }

  return json({ error: "subscription_required" }, 402);
}
