import { toOpenAiSchema } from "./schema.ts";
import type { GenerateJsonOpts, LlmProvider, ToolLoopOpts } from "./types.ts";

interface OpenAiToolCall {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
}
interface OpenAiMessage {
  role: string;
  content?: string | null;
  tool_calls?: OpenAiToolCall[];
}
interface OpenAiResponse {
  choices?: Array<{ message?: OpenAiMessage }>;
}

export class OpenAiProvider implements LlmProvider {
  constructor(
    private apiKey: string,
    private model: string,
    private timeoutMs: number,
    private baseUrl: string = "https://api.openai.com/v1",
  ) {}

  private async post(body: unknown, signal: AbortSignal): Promise<OpenAiResponse> {
    const res = await fetch(`${this.baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${this.apiKey}`,
      },
      signal,
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`openai_http_${res.status}`);
    return await res.json() as OpenAiResponse;
  }

  private parseContent<T>(data: OpenAiResponse): T {
    const content = data.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("openai_empty");
    try {
      return JSON.parse(content) as T;
    } catch {
      throw new Error("openai_bad_json");
    }
  }

  private jsonFormat(schema: unknown) {
    return {
      type: "json_schema",
      json_schema: { name: "result", schema, strict: true },
    };
  }

  async generateJson<T>(opts: GenerateJsonOpts): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const messages: Array<Record<string, unknown>> = [];
      if (opts.system) messages.push({ role: "system", content: opts.system });
      for (const m of opts.messages) messages.push({ role: m.role, content: m.content });
      const last = messages.length > 0 ? messages[messages.length - 1] as { role: string; content: string } : undefined;
      if (opts.image && last && last.role === "user") {
        messages[messages.length - 1] = {
          role: last.role,
          content: [
            { type: "text", text: last.content },
            {
              type: "image_url",
              image_url: { url: `data:${opts.image.mimeType};base64,${opts.image.dataBase64}` },
            },
          ],
        };
      }
      const data = await this.post({
        model: this.model,
        messages,
        temperature: opts.temperature ?? 0.3,
        response_format: this.jsonFormat(toOpenAiSchema(opts.schema)),
      }, controller.signal);
      return this.parseContent<T>(data);
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
      const messages: Array<Record<string, unknown>> = [{ role: "system", content: opts.system }];
      for (const m of opts.messages) messages.push({ role: m.role, content: m.content });
      const tools = opts.tools.map((t) => ({
        type: "function",
        function: {
          name: t.name,
          description: t.description,
          parameters: toOpenAiSchema(t.parameters),
        },
      }));

      let calls = 0;
      while (calls < maxCalls) {
        const data = await this.post({
          model: this.model,
          messages,
          tools,
          tool_choice: "auto",
          temperature,
        }, controller.signal);
        const msg = data.choices?.[0]?.message;
        if (!msg) throw new Error("openai_empty");
        const toolCalls = msg.tool_calls;
        if (!toolCalls || toolCalls.length === 0) break;
        messages.push({
          role: msg.role,
          content: msg.content ?? null,
          tool_calls: msg.tool_calls,
        });
        for (const tc of toolCalls) {
          let args: Record<string, unknown>;
          try {
            args = JSON.parse(tc.function.arguments || "{}") as Record<string, unknown>;
          } catch {
            throw new Error(`openai_bad_tool_args:${tc.function.name}`);
          }
          const result = await opts.executeTool(tc.function.name, args);
          messages.push({
            role: "tool",
            tool_call_id: tc.id,
            content: JSON.stringify(result ?? null),
          });
        }
        calls++;
      }

      const finalData = await this.post({
        model: this.model,
        messages,
        temperature,
        response_format: this.jsonFormat(toOpenAiSchema(opts.finalSchema)),
      }, controller.signal);
      return this.parseContent<T>(finalData);
    } finally {
      clearTimeout(timer);
    }
  }
}
