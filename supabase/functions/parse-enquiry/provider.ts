import { buildPrompt, ParsedEnquiry, responseSchema } from "./schema.ts";

export interface EnquiryParser {
  parse(text: string): Promise<ParsedEnquiry>;
}

class GeminiParser implements EnquiryParser {
  constructor(
    private apiKey: string,
    private model: string,
    private timeoutMs: number,
  ) {}

  async parse(text: string): Promise<ParsedEnquiry> {
    const today = new Date().toISOString().slice(0, 10);
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
          contents: [
            { role: "user", parts: [{ text: buildPrompt(text, today) }] },
          ],
          generationConfig: {
            temperature: 0,
            responseMimeType: "application/json",
            responseSchema,
          },
        }),
      });
      if (!res.ok) {
        // Do not include response body: it may echo chat content.
        throw new Error(`gemini_http_${res.status}`);
      }
      const data = await res.json();
      const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof raw !== "string") throw new Error("gemini_empty");
      return JSON.parse(raw) as ParsedEnquiry;
    } finally {
      clearTimeout(timer);
    }
  }
}

export function createParser(): EnquiryParser {
  const provider = Deno.env.get("AI_PROVIDER") ?? "gemini";
  if (provider === "gemini") {
    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) throw new Error("missing_gemini_key");
    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    const timeoutMs = Number(Deno.env.get("AI_TIMEOUT_MS") ?? "8000");
    return new GeminiParser(key, model, timeoutMs);
  }
  // Future: Claude adapter selected here without changing the handler.
  throw new Error(`unsupported_provider_${provider}`);
}
