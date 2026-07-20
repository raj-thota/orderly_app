import type { NeutralSchema } from "./schema.ts";

export type LlmRole = "user" | "assistant";

export interface LlmMessage {
  role: LlmRole;
  content: string;
}

export interface LlmTool {
  name: string;
  description: string;
  parameters: NeutralSchema;
}

export interface LlmImage {
  mimeType: string;
  dataBase64: string;
}

export interface GenerateJsonOpts {
  system?: string;
  messages: LlmMessage[];
  schema: NeutralSchema;
  temperature?: number;
  image?: LlmImage;
}

export interface ToolLoopOpts {
  system: string;
  messages: LlmMessage[];
  tools: LlmTool[];
  finalSchema: NeutralSchema;
  executeTool: (name: string, args: Record<string, unknown>) => Promise<unknown>;
  maxToolCalls?: number;
  temperature?: number;
}

export interface LlmProvider {
  generateJson<T>(opts: GenerateJsonOpts): Promise<T>;
  runToolLoop<T>(opts: ToolLoopOpts): Promise<T>;
}
