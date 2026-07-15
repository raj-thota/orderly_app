import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { createAssistantProvider } from "./provider.ts";
import type { AssistantInput } from "./schema.ts";

const RATE_MAX = 40;
const RATE_WINDOW_SECONDS = 3600;
const MAX_HISTORY = 10;

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

  // Rate limit: 40 assistant queries per hour.
  const { data: allowed, error: rlErr } = await supabase.rpc(
    "check_ai_rate_limit",
    {
      p_feature: "assistant",
      p_max: RATE_MAX,
      p_window_seconds: RATE_WINDOW_SECONDS,
    },
  );
  if (rlErr) return json({ error: "rate_limit_check_failed" }, 500);
  if (!allowed) return json({ error: "rate_limit_exceeded" }, 429);

  let body: AssistantInput;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const question = body.question?.toString()?.trim();
  if (!question) return json({ error: "missing_question" }, 400);
  if (question.length > 500) return json({ error: "question_too_long" }, 400);

  const history = (Array.isArray(body.history) ? body.history : [])
    .slice(-MAX_HISTORY)
    .filter((h): h is { role: string; content: string } =>
      typeof h?.role === "string" && typeof h?.content === "string"
    );

  // Fetch seller name for system prompt.
  const { data: profile } = await supabase
    .from("business_profile")
    .select("name")
    .eq("user_id", userId)
    .maybeSingle();
  const sellerName = profile?.name ?? "the seller";

  // Fire telemetry (fire-and-forget, no PII).
  supabase.from("app_events").insert({
    user_id: userId,
    event_type: "assistant_query",
    payload: {},
  }).then(() => {});

  const startMs = Date.now();
  try {
    const provider = createAssistantProvider();
    const output = await provider.answer(question, history, supabase, sellerName);

    // Log AI call latency (fire-and-forget).
    supabase.from("app_events").insert({
      user_id: userId,
      event_type: "ai_call",
      payload: { fn: "assistant", ms: Date.now() - startMs, ok: true },
    }).then(() => {});

    return json(output);
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown";

    supabase.from("app_events").insert({
      user_id: userId,
      event_type: "ai_call",
      payload: { fn: "assistant", ms: Date.now() - startMs, ok: false, error: message },
    }).then(() => {});

    if (message.includes("abort") || message.includes("timeout")) {
      return json({ error: "assistant_timeout" }, 504);
    }
    return json({ error: "assistant_error" }, 500);
  }
});
