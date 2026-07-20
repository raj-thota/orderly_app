import { GeminiProvider } from "./gemini.ts";
import { OpenAiProvider } from "./openai.ts";
import type { LlmProvider } from "./types.ts";

/** Resolve and construct the LLM provider for edge function [fn].
 * Precedence: AI_PROVIDER_<FN> > AI_PROVIDER > "gemini". */
export function createProvider(fn: string): LlmProvider {
  const overrideKey = `AI_PROVIDER_${fn.toUpperCase().replace(/-/g, "_")}`;
  // Deliberate: `??` only coalesces null/undefined, so an empty AI_PROVIDER="" is
  // treated as invalid (throws unsupported_provider_) rather than silently defaulting.
  const name = Deno.env.get(overrideKey) ?? Deno.env.get("AI_PROVIDER") ?? "gemini";
  const rawTimeout = Deno.env.get("AI_TIMEOUT_MS") ?? "15000";
  const timeoutMs = Number(rawTimeout);
  if (Number.isNaN(timeoutMs)) throw new Error(`invalid_AI_TIMEOUT_MS:${rawTimeout}`);

  if (name === "gemini") {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) throw new Error("missing_gemini_key");
    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    return new GeminiProvider(apiKey, model, timeoutMs);
  }
  if (name === "openai") {
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) throw new Error("missing_openai_key");
    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
    const baseUrl = Deno.env.get("OPENAI_BASE_URL") ?? "https://api.openai.com/v1";
    return new OpenAiProvider(apiKey, model, timeoutMs, baseUrl);
  }
  throw new Error(`unsupported_provider_${name}`);
}
