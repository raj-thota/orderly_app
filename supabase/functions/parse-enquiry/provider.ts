import {
  buildPrompt,
  ParsedEnquiry,
  ParseInput,
  responseSchema,
} from "./schema.ts";

export interface EnquiryParser {
  parse(input: ParseInput): Promise<ParsedEnquiry>;
}

class GeminiParser implements EnquiryParser {
  constructor(
    private apiKey: string,
    private model: string,
    private timeoutMs: number,
  ) {}

  async parse(input: ParseInput): Promise<ParsedEnquiry> {
    const today = new Date().toISOString().slice(0, 10);
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`;

    const parts: unknown[] = [{ text: buildPrompt(input.text, today) }];
    if (input.image) {
      parts.push({
        inlineData: { mimeType: input.image.mimeType, data: input.image.data },
      });
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: controller.signal,
        body: JSON.stringify({
          contents: [{ role: "user", parts }],
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
      try {
        return JSON.parse(raw) as ParsedEnquiry;
      } catch (_) {
        // Never surface the payload fragment JSON.parse embeds in its message.
        throw new Error("gemini_bad_json");
      }
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
