import { toGeminiSchema } from "./schema.ts";
import type { NeutralSchema } from "./schema.ts";
import type { GenerateJsonOpts, LlmProvider, ToolLoopOpts } from "./types.ts";

interface GeminiPart {
  text?: string;
  functionCall?: { name: string; args?: Record<string, unknown> };
}
interface GeminiResponse {
  candidates?: Array<{ content?: { parts?: GeminiPart[] } }>;
}

export class GeminiProvider implements LlmProvider {
  constructor(
    private apiKey: string,
    private model: string,
    private timeoutMs: number,
  ) {}

  private url(): string {
    return `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent`;
  }

  private async post(body: unknown, signal: AbortSignal): Promise<GeminiResponse> {
    const res = await fetch(this.url(), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": this.apiKey,
      },
      signal,
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`gemini_http_${res.status}`);
    return await res.json() as GeminiResponse;
  }

  private parseJson<T>(data: GeminiResponse): T {
    const raw = data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof raw !== "string") throw new Error("gemini_empty");
    try {
      return JSON.parse(raw) as T;
    } catch {
      throw new Error("gemini_bad_json");
    }
  }

  async generateJson<T>(opts: GenerateJsonOpts): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const contents = opts.messages.map((m) => ({
        role: m.role === "assistant" ? "model" : "user",
        parts: [{ text: m.content }] as Record<string, unknown>[],
      }));
      if (opts.image && contents.length > 0) {
        contents[contents.length - 1].parts.push({
          inlineData: { mimeType: opts.image.mimeType, data: opts.image.dataBase64 },
        });
      }
      const body: Record<string, unknown> = {
        contents,
        generationConfig: {
          temperature: opts.temperature ?? 0.3,
          responseMimeType: "application/json",
          responseSchema: toGeminiSchema(opts.schema),
        },
      };
      if (opts.system) body.system_instruction = { parts: [{ text: opts.system }] };
      return this.parseJson<T>(await this.post(body, controller.signal));
    } finally {
      clearTimeout(timer);
    }
  }

  async runToolLoop<T>(opts: ToolLoopOpts): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const maxCalls = opts.maxToolCalls ?? 3;
      const temperature = opts.temperature ?? 0.3;
      const systemInstruction = { parts: [{ text: opts.system }] };
      const contents: Array<{ role: string; parts: Record<string, unknown>[] }> = opts.messages
        .map((m) => ({
          role: m.role === "assistant" ? "model" : "user",
          parts: [{ text: m.content }],
        }));
      const toolDecl = {
        function_declarations: opts.tools.map((t) => ({
          name: t.name,
          description: t.description,
          parameters: toGeminiSchema(t.parameters),
        })),
      };

      let toolCallCount = 0;
      while (toolCallCount < maxCalls) {
        const data = await this.post({
          system_instruction: systemInstruction,
          contents,
          tools: [toolDecl],
          tool_config: { function_calling_config: { mode: "AUTO" } },
          generationConfig: { temperature },
        }, controller.signal);
        const parts = data.candidates?.[0]?.content?.parts ?? [];
        const fnPart = parts.find((p) => p.functionCall);
        if (!fnPart?.functionCall) {
          // Model stopped calling tools — this fetch IS the final answer; make one
          // more structured call to get JSON output.
          break;
        }
        const { name, args } = fnPart.functionCall;
        contents.push({ role: "model", parts: [{ functionCall: fnPart.functionCall }] });
        const result = await opts.executeTool(name, args ?? {});
        contents.push({
          role: "user",
          parts: [{ functionResponse: { name, response: { result } } }],
        });
        toolCallCount++;
      }

      const finalData = await this.post({
        system_instruction: systemInstruction,
        contents,
        generationConfig: {
          temperature,
          responseMimeType: "application/json",
          responseSchema: toGeminiSchema(opts.finalSchema),
        },
      }, controller.signal);
      return this.parseJson<T>(finalData);
    } finally {
      clearTimeout(timer);
    }
  }
}
