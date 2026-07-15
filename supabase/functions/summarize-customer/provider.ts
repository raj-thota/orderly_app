import {
  buildPrompt,
  SummarizeInput,
  SummarizeOutput,
  responseSchema,
} from "./schema.ts";

export interface SummarizeProvider {
  summarize(input: SummarizeInput): Promise<SummarizeOutput>;
}

class GeminiSummarizeProvider implements SummarizeProvider {
  constructor(
    private apiKey: string,
    private model: string,
    private timeoutMs: number,
  ) {}

  async summarize(input: SummarizeInput): Promise<SummarizeOutput> {
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: controller.signal,
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: buildPrompt(input) }] }],
          generationConfig: {
            temperature: 0.2,
            responseMimeType: "application/json",
            responseSchema,
          },
        }),
      });
      if (!res.ok) throw new Error(`gemini_http_${res.status}`);
      const data = await res.json();
      const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof raw !== "string") throw new Error("gemini_empty");
      try {
        return JSON.parse(raw) as SummarizeOutput;
      } catch (_) {
        throw new Error("gemini_bad_json");
      }
    } finally {
      clearTimeout(timer);
    }
  }
}

export function createSummarizeProvider(): SummarizeProvider {
  const provider = Deno.env.get("AI_PROVIDER") ?? "gemini";
  if (provider === "gemini") {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) throw new Error("missing_gemini_key");
    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    const timeoutMs = Number(Deno.env.get("AI_TIMEOUT_MS") ?? "12000");
    return new GeminiSummarizeProvider(key, model, timeoutMs);
  }
  throw new Error(`unsupported_provider_${provider}`);
}
