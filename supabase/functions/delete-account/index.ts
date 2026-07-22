import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";

// Permanently deletes the signed-in user's account. Every owned table
// (customers, orders, messages, invoices, subscriptions, ...) is
// `references auth.users(id) on delete cascade`, so removing the auth user
// erases all their data in one shot. Required for App Store 5.1.1(v) and
// Google Play account-deletion policy.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  // 1. Resolve the caller from their JWT (never trust a client-supplied id).
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return json({ error: "unauthorized" }, 401);
  const userId = userData.user.id;

  // 2. Hard-delete the auth user with the service role; FK cascade wipes data.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { error: delErr } = await admin.auth.admin.deleteUser(userId);
  if (delErr) {
    console.error(`delete_account_failed:${delErr.message}`);
    return json({ error: "delete_failed" }, 500);
  }

  return json({ ok: true }, 200);
});
