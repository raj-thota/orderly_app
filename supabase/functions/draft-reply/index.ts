import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { createProvider } from "../_shared/ai/factory.ts";
import { DraftInput, draftReplyPrompt, draftReplySchema } from "../_shared/ai/prompts/draft-reply.ts";

const RATE_MAX = 60;
const RATE_WINDOW_SECONDS = 3600;
const ALLOWED_OBJECTIVES = new Set(["reply", "payment_reminder", "follow_up", "nudge"]);
const MAX_MESSAGES = 20;

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
  const objective = typeof body.objective === "string" ? body.objective : "";

  if (!customerId || !ALLOWED_OBJECTIVES.has(objective)) {
    return json({ error: "bad_request" }, 400);
  }

  // Rate limit before expensive DB reads.
  const { data: allowed, error: rlErr } = await supabase.rpc(
    "check_ai_parse_rate_limit",
    { p_max: RATE_MAX, p_window_seconds: RATE_WINDOW_SECONDS },
  );
  if (rlErr) return json({ error: "internal" }, 500);
  if (allowed !== true) return json({ error: "rate_limited" }, 429);

  // Load conversation context from DB. Amounts, phone numbers, UPI IDs
  // are intentionally NOT passed to the model — prose only.
  const { data: convRow } = await supabase
    .from("conversations")
    .select("id")
    .eq("user_id", userId)
    .eq("customer_id", customerId)
    .maybeSingle();

  const messages: { direction: string; body: string }[] = [];
  if (convRow?.id) {
    const { data: msgRows } = await supabase
      .from("messages")
      .select("direction, body")
      .eq("user_id", userId)
      .eq("conversation_id", convRow.id)
      .order("created_at", { ascending: false })
      .limit(MAX_MESSAGES);
    if (msgRows) {
      messages.push(...msgRows.reverse());
    }
  }

  const { data: customerRow } = await supabase
    .from("customers")
    .select("name")
    .eq("id", customerId)
    .eq("user_id", userId)
    .maybeSingle();

  const { data: bizRow } = await supabase
    .from("business_profile")
    .select("name")
    .eq("user_id", userId)
    .maybeSingle();

  const { data: leadRow } = await supabase
    .from("leads")
    .select("message, intent")
    .eq("customer_id", customerId)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  try {
    const provider = createProvider("draft-reply");
    const input: DraftInput = {
      customerId,
      objective: objective as DraftInput["objective"],
      messages,
      customerName: customerRow?.name ?? null,
      outstandingAmount: null, // never from model; client reads from DB
      enquiryContext: leadRow?.message ?? null,
    };
    const result = await provider.generateJson<{ message: string; confidence: number }>({
      messages: [{ role: "user", content: draftReplyPrompt(input, bizRow?.name ?? "Seller") }],
      schema: draftReplySchema,
      temperature: 0.4,
    });
    const confidence = Math.min(1, Math.max(0, result.confidence));
    return json({ message: result.message, confidence }, 200);
  } catch (e) {
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`draft_reply_failed:${label}`);
    return json({ error: "draft_failed" }, 502);
  }
});
