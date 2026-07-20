import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { createProvider } from "../_shared/ai/factory.ts";
import {
  assistantFinalSchema,
  assistantSystemPrompt,
  assistantTools,
  PII_PATTERN,
} from "../_shared/ai/prompts/assistant.ts";
import type { AssistantInput, AssistantOutput } from "./schema.ts";

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
    const provider = createProvider("assistant");
    const output = await provider.runToolLoop<AssistantOutput>({
      system: assistantSystemPrompt(sellerName),
      messages: [
        ...history.map((h) => ({
          role: h.role === "assistant" ? "assistant" as const : "user" as const,
          content: h.content,
        })),
        { role: "user" as const, content: question },
      ],
      tools: assistantTools,
      finalSchema: assistantFinalSchema,
      maxToolCalls: 3,
      temperature: 0.3,
      executeTool: async (name, args) => {
        const limit = Math.min(Number(args.limit ?? 10), 20);
        switch (name) {
          case "outstanding_summary": {
            const { data, error } = await supabase.rpc("assistant_outstanding_summary", { p_limit: limit });
            if (error) throw new Error(`rpc_outstanding_${error.code}`);
            return data;
          }
          case "top_customers": {
            const { data, error } = await supabase.rpc("assistant_top_customers", { p_limit: limit });
            if (error) throw new Error(`rpc_top_customers_${error.code}`);
            return data;
          }
          case "pipeline_stats": {
            const { data, error } = await supabase.rpc("assistant_pipeline_stats");
            if (error) throw new Error(`rpc_pipeline_stats_${error.code}`);
            return data;
          }
          case "overdue_followups": {
            const { data, error } = await supabase.rpc("assistant_overdue_followups", { p_limit: limit });
            if (error) throw new Error(`rpc_overdue_followups_${error.code}`);
            return data;
          }
          default:
            throw new Error(`unknown_tool_${name}`);
        }
      },
    });

    // PII guard: strip any proposed items whose draft leaks sensitive data.
    output.proposed_work_items = (output.proposed_work_items ?? []).filter(
      (item) => !PII_PATTERN.test(item.draft_message),
    );

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
