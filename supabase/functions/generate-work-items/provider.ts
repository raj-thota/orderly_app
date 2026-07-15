import { buildPrompt, GenerateInput, GenerateOutput, responseSchema } from "./schema.ts";

export interface WorkItemsProvider {
  generate(input: GenerateInput): Promise<GenerateOutput>;
}

class GeminiWorkItemsProvider implements WorkItemsProvider {
  constructor(
    private apiKey: string,
    private model: string,
    private timeoutMs: number,
  ) {}

  async generate(input: GenerateInput): Promise<GenerateOutput> {
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
            temperature: 0.3,
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
        const parsed = JSON.parse(raw) as GenerateOutput;
        return parsed;
      } catch (_) {
        throw new Error("gemini_bad_json");
      }
    } finally {
      clearTimeout(timer);
    }
  }
}

export function createWorkItemsProvider(): WorkItemsProvider {
  const provider = Deno.env.get("AI_PROVIDER") ?? "gemini";
  if (provider === "gemini") {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) throw new Error("missing_gemini_key");
    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    const timeoutMs = Number(Deno.env.get("AI_TIMEOUT_MS") ?? "15000");
    return new GeminiWorkItemsProvider(key, model, timeoutMs);
  }
  throw new Error(`unsupported_provider_${provider}`);
}
