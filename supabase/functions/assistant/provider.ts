import {
  AssistantOutput,
  assistantTools,
  buildSystemPrompt,
  finalResponseSchema,
  PII_PATTERN,
} from "./schema.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export interface AssistantProvider {
  answer(
    question: string,
    history: Array<{ role: string; content: string }>,
    supabase: SupabaseClient,
    sellerName: string,
  ): Promise<AssistantOutput>;
}

class GeminiAssistantProvider implements AssistantProvider {
  constructor(
    private apiKey: string,
    private model: string,
    private timeoutMs: number,
  ) {}

  async answer(
    question: string,
    history: Array<{ role: string; content: string }>,
    supabase: SupabaseClient,
    sellerName: string,
  ): Promise<AssistantOutput> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      return await this._runToolLoop(question, history, supabase, sellerName, controller.signal);
    } finally {
      clearTimeout(timer);
    }
  }

  private async _runToolLoop(
    question: string,
    history: Array<{ role: string; content: string }>,
    supabase: SupabaseClient,
    sellerName: string,
    signal: AbortSignal,
  ): Promise<AssistantOutput> {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`;

    // Build conversation history in Gemini format.
    const contents: Array<{ role: string; parts: Array<{ text?: string; functionCall?: unknown; functionResponse?: unknown }> }> = [
      ...history.map((h) => ({
        role: h.role === "assistant" ? "model" : "user",
        parts: [{ text: h.content }],
      })),
      { role: "user", parts: [{ text: question }] },
    ];

    let toolCallCount = 0;
    const MAX_TOOL_CALLS = 3;

    // Phase 1: Tool-calling loop.
    while (toolCallCount < MAX_TOOL_CALLS) {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal,
        body: JSON.stringify({
          system_instruction: { parts: [{ text: buildSystemPrompt(sellerName) }] },
          contents,
          tools: [{ function_declarations: assistantTools }],
          tool_config: { function_calling_config: { mode: "AUTO" } },
          generationConfig: { temperature: 0.3 },
        }),
      });

      if (!res.ok) throw new Error(`gemini_http_${res.status}`);
      const data = await res.json();
      const candidate = data?.candidates?.[0];
      if (!candidate) throw new Error("gemini_empty");

      const parts = candidate.content?.parts ?? [];
      const fnCall = parts.find((p: { functionCall?: { name: string; args: Record<string, unknown> } }) => p.functionCall);

      if (!fnCall?.functionCall) {
        // Model gave a text response — go to final structured response.
        break;
      }

      // Execute the tool call.
      const { name, args } = fnCall.functionCall as { name: string; args: Record<string, unknown> };
      const toolResult = await this._executeTool(name, args, supabase);

      // Feed result back into conversation.
      contents.push({ role: "model", parts: [{ functionCall: fnCall.functionCall }] });
      contents.push({
        role: "user",
        parts: [{
          functionResponse: {
            name,
            response: { result: toolResult },
          },
        }],
      });
      toolCallCount++;
    }

    // Phase 2: Final structured response with schema enforcement.
    const finalRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal,
      body: JSON.stringify({
        system_instruction: { parts: [{ text: buildSystemPrompt(sellerName) }] },
        contents,
        generationConfig: {
          temperature: 0.3,
          responseMimeType: "application/json",
          responseSchema: finalResponseSchema,
        },
      }),
    });

    if (!finalRes.ok) throw new Error(`gemini_final_http_${finalRes.status}`);
    const finalData = await finalRes.json();
    const rawText = finalData?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof rawText !== "string") throw new Error("gemini_final_empty");

    let output: AssistantOutput;
    try {
      output = JSON.parse(rawText);
    } catch {
      throw new Error("gemini_final_bad_json");
    }

    // PII guard: strip any proposed items whose draft leaks sensitive data.
    output.proposed_work_items = (output.proposed_work_items ?? []).filter(
      (item) => !PII_PATTERN.test(item.draft_message),
    );

    return output;
  }

  private async _executeTool(
    name: string,
    args: Record<string, unknown>,
    supabase: SupabaseClient,
  ): Promise<unknown> {
    switch (name) {
      case "outstanding_summary": {
        const limit = Math.min(Number(args.limit ?? 10), 20);
        const { data, error } = await supabase.rpc("assistant_outstanding_summary", { p_limit: limit });
        if (error) throw new Error(`rpc_outstanding_${error.code}`);
        return data;
      }
      case "top_customers": {
        const limit = Math.min(Number(args.limit ?? 10), 20);
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
        const limit = Math.min(Number(args.limit ?? 10), 20);
        const { data, error } = await supabase.rpc("assistant_overdue_followups", { p_limit: limit });
        if (error) throw new Error(`rpc_overdue_followups_${error.code}`);
        return data;
      }
      default:
        throw new Error(`unknown_tool_${name}`);
    }
  }
}

export function createAssistantProvider(): AssistantProvider {
  const provider = Deno.env.get("AI_PROVIDER") ?? "gemini";
  if (provider === "gemini") {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) throw new Error("missing_gemini_key");
    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    const timeoutMs = Number(Deno.env.get("AI_TIMEOUT_MS") ?? "15000");
    return new GeminiAssistantProvider(key, model, timeoutMs);
  }
  throw new Error(`unsupported_provider_${provider}`);
}
