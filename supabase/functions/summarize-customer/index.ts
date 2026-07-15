import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { createSummarizeProvider } from "./provider.ts";
import { createHash } from "node:crypto";

const RATE_MAX = 30;
const RATE_WINDOW_SECONDS = 3600;
const MAX_MESSAGES = 50;

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

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }

  const customerId = typeof body.customer_id === "string" ? body.customer_id.trim() : "";
  if (!customerId) return json({ error: "bad_request" }, 400);

  // Rate limit.
  const { data: allowed, error: rlErr } = await supabase.rpc(
    "check_ai_parse_rate_limit",
    { p_max: RATE_MAX, p_window_seconds: RATE_WINDOW_SECONDS },
  );
  if (rlErr) return json({ error: "internal" }, 500);
  if (allowed !== true) return json({ error: "rate_limited" }, 429);

  // Load messages.
  const { data: convRow } = await supabase
    .from("conversations")
    .select("id")
    .eq("user_id", userId)
    .eq("customer_id", customerId)
    .maybeSingle();

  const messages: { id: string; direction: string; body: string }[] = [];
  if (convRow?.id) {
    const { data: msgRows } = await supabase
      .from("messages")
      .select("id, direction, body, created_at")
      .eq("user_id", userId)
      .eq("conversation_id", convRow.id)
      .order("created_at", { ascending: true })
      .limit(MAX_MESSAGES);
    if (msgRows) messages.push(...msgRows);
  }

  if (messages.length === 0) {
    return json({ error: "no_messages" }, 422);
  }

  // Check source_hash to skip unchanged conversations.
  const sourceHash = createHash("sha256")
    .update(messages.map((m) => m.id).join(","))
    .digest("hex");

  const { data: existingSummary } = await supabase
    .from("ai_summaries")
    .select("source_hash, bullets, close_confidence")
    .eq("user_id", userId)
    .eq("customer_id", customerId)
    .maybeSingle();

  if (existingSummary?.source_hash === sourceHash) {
    return json({ cached: true, source_hash: sourceHash }, 200);
  }

  const { data: customerRow } = await supabase
    .from("customers")
    .select("name, ai_facts")
    .eq("id", customerId)
    .eq("user_id", userId)
    .maybeSingle();

  const existingFacts = Array.isArray(customerRow?.ai_facts)
    ? (customerRow.ai_facts as { fact: string }[])
    : [];

  try {
    const provider = createSummarizeProvider();
    const result = await provider.summarize({
      customerName: customerRow?.name ?? null,
      messages,
      existingFacts,
    });

    // Clamp confidence.
    const conf = Math.min(1, Math.max(0, result.close_confidence));

    // Upsert ai_summaries.
    await supabase.from("ai_summaries").upsert(
      {
        user_id: userId,
        customer_id: customerId,
        bullets: result.bullets,
        close_confidence: conf,
        source_hash: sourceHash,
        created_at: new Date().toISOString(),
      },
      { onConflict: "user_id,customer_id" },
    );

    // Merge new facts into customers.ai_facts (dedup by normalized text).
    if (result.facts.length > 0) {
      const existingNorm = new Set(
        existingFacts.map((f) => f.fact.toLowerCase().trim()),
      );
      const newFacts = result.facts.filter(
        (f) => !existingNorm.has(f.fact.toLowerCase().trim()),
      );
      if (newFacts.length > 0) {
        const merged = [...existingFacts, ...newFacts];
        await supabase
          .from("customers")
          .update({ ai_facts: merged })
          .eq("id", customerId)
          .eq("user_id", userId);
      }
    }

    return json(
      { bullets: result.bullets, close_confidence: conf, facts: result.facts },
      200,
    );
  } catch (e) {
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`summarize_failed:${label}`);
    return json({ error: "summarize_failed" }, 502);
  }
});
