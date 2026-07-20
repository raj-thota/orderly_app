# AI Provider Abstraction + Prompt Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the five copy-pasted, Gemini-only edge-function providers with one shared `_shared/ai/` abstraction (Gemini **+ OpenAI**, full parity) and a central Prompt Manager, without changing external behavior.

**Architecture:** A two-capability `LlmProvider` interface (`generateJson` for single-shot structured JSON, `runToolLoop` for tool-calling → structured final). Schemas authored once as a neutral lowercase JSON-Schema and translated per provider (`toGeminiSchema` uppercases types; `toOpenAiSchema` emits `strict` json_schema with `additionalProperties:false` and null-unions for optional fields). A `createProvider(fn)` factory resolves `AI_PROVIDER_<FN>` → `AI_PROVIDER` → `gemini`. All prompts/tools/schemas move to `_shared/ai/prompts/`. Each function refactors onto this and deletes its `provider.ts`.

**Tech Stack:** Deno (Supabase edge functions), TypeScript, `jsr:@std/assert` for tests. Providers call Gemini `generateContent` and OpenAI `chat/completions` via `fetch` (mocked in tests).

**Verification commands:**
- Unit tests: `deno test --allow-env supabase/functions/_shared/ai/`
- Typecheck everything: `deno check supabase/functions/**/*.ts`

**Reference spec:** `docs/superpowers/specs/2026-07-20-ai-provider-abstraction-design.md`

**Behavior-parity facts (preserve exactly):**
- Per-function temperature: assistant `0.3`, generate-work-items `0.3`, parse-enquiry `0`, draft-reply `0.4`, summarize-customer `0.2`. Passed via `opts.temperature`.
- Gemini default model `gemini-2.5-flash`; default provider `gemini` (prod unchanged).
- Assistant tool loop: ≤3 tool calls, `AUTO` mode, then a final structured call. PII filter stays in the assistant `index.ts`.
- Per-function request timeouts unify to a single `AI_TIMEOUT_MS` (default `15000`). This lengthens parse-enquiry (was 8000), draft-reply (was 6000), and summarize-customer (was 12000) — intentional, more lenient.

---

## File Structure

**New — shared AI lib**
- `supabase/functions/_shared/ai/schema.ts` — `NeutralSchema` type + `toGeminiSchema` + `toOpenAiSchema`.
- `supabase/functions/_shared/ai/types.ts` — `LlmMessage`, `LlmTool`, `LlmImage`, `GenerateJsonOpts`, `ToolLoopOpts`, `LlmProvider`.
- `supabase/functions/_shared/ai/gemini.ts` — `GeminiProvider`.
- `supabase/functions/_shared/ai/openai.ts` — `OpenAiProvider`.
- `supabase/functions/_shared/ai/factory.ts` — `createProvider(fn)`.
- `supabase/functions/_shared/ai/prompts/assistant.ts` — `assistantSystemPrompt`, `assistantTools`, `assistantFinalSchema`, `PII_PATTERN`.
- `supabase/functions/_shared/ai/prompts/work-items.ts` — `CustomerSignal`, `GenerateInput`, `workItemsPrompt`, `workItemsSchema`.
- `supabase/functions/_shared/ai/prompts/draft-reply.ts` — `DraftObjective`, `DraftInput`, `draftReplyPrompt`, `draftReplySchema`.
- `supabase/functions/_shared/ai/prompts/summarize-customer.ts` — `SummarizeInput`, `summarizePrompt`, `summarizeSchema`.
- `supabase/functions/_shared/ai/prompts/parse-enquiry.ts` — `parseEnquiryPrompt`, `parseEnquirySchema`.

**New — config + tests**
- `supabase/functions/deno.json`
- `supabase/functions/_shared/ai/schema_test.ts`
- `supabase/functions/_shared/ai/gemini_test.ts`
- `supabase/functions/_shared/ai/openai_test.ts`
- `supabase/functions/_shared/ai/factory_test.ts`

**Modified — functions (refactor onto shared lib, delete local provider.ts)**
- `supabase/functions/assistant/index.ts` (+ delete `assistant/provider.ts`; slim `assistant/schema.ts` to output types)
- `supabase/functions/generate-work-items/index.ts` (+ delete `provider.ts`; slim `schema.ts` to output types)
- `supabase/functions/draft-reply/index.ts` (+ delete `provider.ts`; slim `schema.ts` to output types)
- `supabase/functions/summarize-customer/index.ts` (+ delete `provider.ts`; slim `schema.ts` to output types)
- `supabase/functions/parse-enquiry/index.ts` (+ delete `provider.ts`; slim `schema.ts` to output types)

---

## Task 1: Deno setup + neutral schema translators

**Files:**
- Create: `supabase/functions/deno.json`
- Create: `supabase/functions/_shared/ai/schema.ts`
- Create: `supabase/functions/_shared/ai/types.ts`
- Test: `supabase/functions/_shared/ai/schema_test.ts`

- [ ] **Step 1: Install Deno and verify**

```bash
which deno || curl -fsSL https://deno.land/install.sh | sh
export PATH="$HOME/.deno/bin:$PATH"
deno --version
```
Expected: prints a `deno x.y.z` version line. (If `deno` still isn't found, add `$HOME/.deno/bin` to PATH for the shell running the remaining steps.)

- [ ] **Step 2: Create `supabase/functions/deno.json`**

```json
{
  "tasks": {
    "test": "deno test --allow-env _shared/ai/",
    "check": "deno check **/*.ts"
  },
  "lint": { "rules": { "tags": ["recommended"] } },
  "fmt": { "lineWidth": 100 }
}
```

- [ ] **Step 3: Write the failing translator tests `_shared/ai/schema_test.ts`**

```ts
import { assertEquals } from "jsr:@std/assert";
import { NeutralSchema, toGeminiSchema, toOpenAiSchema } from "./schema.ts";

const parseEnquiryLike: NeutralSchema = {
  type: "object",
  properties: {
    customer_name: { type: "string", nullable: true },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          qty: { type: "integer" },
          price: { type: "number", nullable: true },
        },
        required: ["name", "qty"],
      },
    },
    intent: { type: "string", enum: ["inquiry", "order", "follow_up"] },
    confidence: { type: "number" },
  },
  required: ["items", "intent", "confidence"],
};

Deno.test("toGeminiSchema uppercases types and preserves enum/required/nullable", () => {
  const g = toGeminiSchema(parseEnquiryLike) as Record<string, unknown>;
  assertEquals(g.type, "OBJECT");
  const props = g.properties as Record<string, Record<string, unknown>>;
  assertEquals(props.customer_name.type, "STRING");
  assertEquals(props.customer_name.nullable, true);
  assertEquals(props.intent.enum, ["inquiry", "order", "follow_up"]);
  assertEquals((props.items.items as Record<string, unknown>).type, "OBJECT");
  assertEquals(g.required, ["items", "intent", "confidence"]);
  // Gemini schema must NOT carry additionalProperties.
  assertEquals("additionalProperties" in g, false);
});

Deno.test("toOpenAiSchema makes all props required, adds additionalProperties:false, null-unions optionals", () => {
  const o = toOpenAiSchema(parseEnquiryLike) as Record<string, unknown>;
  assertEquals(o.type, "object");
  assertEquals(o.additionalProperties, false);
  assertEquals(
    (o.required as string[]).sort(),
    ["confidence", "customer_name", "intent", "items"],
  );
  const props = o.properties as Record<string, Record<string, unknown>>;
  // Optional/nullable -> ["string","null"].
  assertEquals(props.customer_name.type, ["string", "null"]);
  // Required scalar stays a plain string type.
  assertEquals(props.confidence.type, "number");
  // Nested object: price is nullable -> union; name/qty required plain.
  const item = props.items.items as Record<string, unknown>;
  assertEquals(item.additionalProperties, false);
  assertEquals((item.required as string[]).sort(), ["name", "price", "qty"]);
  const itemProps = item.properties as Record<string, Record<string, unknown>>;
  assertEquals(itemProps.price.type, ["number", "null"]);
  assertEquals(itemProps.name.type, "string");
  // OpenAI schema must NOT carry the `nullable` keyword.
  assertEquals("nullable" in props.customer_name, false);
});

Deno.test("toOpenAiSchema treats missing `required` as all-required", () => {
  const s: NeutralSchema = {
    type: "object",
    properties: { a: { type: "string" }, b: { type: "integer" } },
  };
  const o = toOpenAiSchema(s) as Record<string, unknown>;
  assertEquals((o.required as string[]).sort(), ["a", "b"]);
  const props = o.properties as Record<string, Record<string, unknown>>;
  assertEquals(props.a.type, "string");
  assertEquals(props.b.type, "integer");
});
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/schema_test.ts`
Expected: FAIL — `schema.ts` does not exist.

- [ ] **Step 5: Create `_shared/ai/schema.ts`**

```ts
export interface NeutralSchema {
  type: "object" | "array" | "string" | "integer" | "number" | "boolean";
  description?: string;
  properties?: Record<string, NeutralSchema>;
  items?: NeutralSchema;
  enum?: string[];
  required?: string[];
  nullable?: boolean;
}

const GEMINI_TYPE: Record<NeutralSchema["type"], string> = {
  object: "OBJECT",
  array: "ARRAY",
  string: "STRING",
  integer: "INTEGER",
  number: "NUMBER",
  boolean: "BOOLEAN",
};

/** Translate a neutral schema to Gemini's `responseSchema` dialect (uppercase
 * types, `nullable` keyword, partial `required` allowed). */
export function toGeminiSchema(s: NeutralSchema): Record<string, unknown> {
  const out: Record<string, unknown> = { type: GEMINI_TYPE[s.type] };
  if (s.description) out.description = s.description;
  if (s.enum) out.enum = s.enum;
  if (s.nullable) out.nullable = true;
  if (s.properties) {
    out.properties = Object.fromEntries(
      Object.entries(s.properties).map(([k, v]) => [k, toGeminiSchema(v)]),
    );
  }
  if (s.items) out.items = toGeminiSchema(s.items);
  if (s.required) out.required = s.required;
  return out;
}

/** Translate a neutral schema to an OpenAI `strict` json_schema: every property
 * is `required`, objects set `additionalProperties:false`, and optional/nullable
 * properties become `["<type>","null"]` unions (OpenAI has no `nullable`). */
export function toOpenAiSchema(s: NeutralSchema): Record<string, unknown> {
  if (s.type === "object" && s.properties) {
    const keys = Object.keys(s.properties);
    const requiredSet = new Set(s.required ?? keys);
    const properties = Object.fromEntries(
      keys.map((k) => {
        const prop = s.properties![k];
        const optional = !requiredSet.has(k);
        const effective = optional && !prop.nullable ? { ...prop, nullable: true } : prop;
        return [k, toOpenAiSchema(effective)];
      }),
    );
    const out: Record<string, unknown> = {
      type: s.nullable ? ["object", "null"] : "object",
      properties,
      required: keys,
      additionalProperties: false,
    };
    if (s.description) out.description = s.description;
    return out;
  }

  const out: Record<string, unknown> = {
    type: s.nullable ? [s.type, "null"] : s.type,
  };
  if (s.description) out.description = s.description;
  if (s.enum) out.enum = s.enum;
  if (s.items) out.items = toOpenAiSchema(s.items);
  return out;
}
```

- [ ] **Step 6: Create `_shared/ai/types.ts`**

```ts
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
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/schema_test.ts`
Expected: PASS (3 tests). Then `deno check _shared/ai/schema.ts _shared/ai/types.ts` → no errors.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/deno.json supabase/functions/_shared/ai/schema.ts supabase/functions/_shared/ai/types.ts supabase/functions/_shared/ai/schema_test.ts
git commit -m "feat(ai): neutral schema + Gemini/OpenAI translators"
```

---

## Task 2: GeminiProvider

**Files:**
- Create: `supabase/functions/_shared/ai/gemini.ts`
- Test: `supabase/functions/_shared/ai/gemini_test.ts`

- [ ] **Step 1: Write the failing tests `_shared/ai/gemini_test.ts`**

```ts
import { assertEquals, assertRejects } from "jsr:@std/assert";
import { GeminiProvider } from "./gemini.ts";
import type { NeutralSchema } from "./schema.ts";

const schema: NeutralSchema = {
  type: "object",
  properties: { answer: { type: "string" } },
  required: ["answer"],
};

interface Captured { url: string; body: Record<string, unknown>; }

function stubFetch(responses: unknown[]): { calls: Captured[]; restore: () => void } {
  const original = globalThis.fetch;
  const calls: Captured[] = [];
  let i = 0;
  globalThis.fetch = ((url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), body: JSON.parse(String(init?.body ?? "{}")) });
    const payload = responses[Math.min(i, responses.length - 1)];
    i++;
    return Promise.resolve(new Response(JSON.stringify(payload), { status: 200 }));
  }) as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

function geminiText(obj: unknown) {
  return { candidates: [{ content: { parts: [{ text: JSON.stringify(obj) }] } }] };
}

Deno.test("generateJson builds a generateContent body and parses candidate text", async () => {
  const { calls, restore } = stubFetch([geminiText({ answer: "hi" })]);
  try {
    const p = new GeminiProvider("KEY", "gemini-2.5-flash", 5000);
    const out = await p.generateJson<{ answer: string }>({
      messages: [{ role: "user", content: "hello" }],
      schema,
      temperature: 0.3,
    });
    assertEquals(out.answer, "hi");
    const body = calls[0].body;
    const gc = body.generationConfig as Record<string, unknown>;
    assertEquals(gc.responseMimeType, "application/json");
    assertEquals((gc.responseSchema as Record<string, unknown>).type, "OBJECT");
    assertEquals(gc.temperature, 0.3);
    const contents = body.contents as Array<{ role: string; parts: unknown[] }>;
    assertEquals(contents[0].role, "user");
  } finally { restore(); }
});

Deno.test("generateJson appends an inline image part", async () => {
  const { calls, restore } = stubFetch([geminiText({ answer: "ok" })]);
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    await p.generateJson({
      messages: [{ role: "user", content: "read this" }],
      schema,
      image: { mimeType: "image/png", dataBase64: "AAAA" },
    });
    const contents = calls[0].body.contents as Array<{ parts: Record<string, unknown>[] }>;
    const parts = contents[0].parts;
    assertEquals((parts[1].inlineData as Record<string, unknown>).mimeType, "image/png");
  } finally { restore(); }
});

Deno.test("runToolLoop executes a tool, feeds result back, then makes the final structured call", async () => {
  const calledTools: Array<{ name: string; args: Record<string, unknown> }> = [];
  const responses = [
    { candidates: [{ content: { parts: [{ functionCall: { name: "pipeline_stats", args: {} } }] } }] },
    geminiText({ answer: "done" }),
  ];
  const { calls, restore } = stubFetch(responses);
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    const out = await p.runToolLoop<{ answer: string }>({
      system: "sys",
      messages: [{ role: "user", content: "stats?" }],
      tools: [{ name: "pipeline_stats", description: "d", parameters: { type: "object" } }],
      finalSchema: schema,
      executeTool: (name, args) => { calledTools.push({ name, args }); return Promise.resolve({ leads: 3 }); },
    });
    assertEquals(out.answer, "done");
    assertEquals(calledTools[0].name, "pipeline_stats");
    // Second (final) call carries a responseSchema; first (tool) call carries tools.
    assertEquals("tools" in calls[0].body, true);
    const finalGc = calls[1].body.generationConfig as Record<string, unknown>;
    assertEquals(finalGc.responseMimeType, "application/json");
  } finally { restore(); }
});

Deno.test("runToolLoop stops after maxToolCalls even if the model keeps calling tools", async () => {
  let toolExecs = 0;
  const toolResp = { candidates: [{ content: { parts: [{ functionCall: { name: "t", args: {} } }] } }] };
  const { calls, restore } = stubFetch([toolResp, toolResp, toolResp, geminiText({ answer: "x" })]);
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    await p.runToolLoop({
      system: "s",
      messages: [{ role: "user", content: "go" }],
      tools: [{ name: "t", description: "d", parameters: { type: "object" } }],
      finalSchema: schema,
      executeTool: () => { toolExecs++; return Promise.resolve({}); },
      maxToolCalls: 2,
    });
    assertEquals(toolExecs, 2);
    // 2 tool-loop calls + 1 final call = 3 fetches.
    assertEquals(calls.length, 3);
  } finally { restore(); }
});

Deno.test("generateJson throws on non-200", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response("no", { status: 500 }))) as typeof fetch;
  try {
    const p = new GeminiProvider("KEY", "m", 5000);
    await assertRejects(
      () => p.generateJson({ messages: [{ role: "user", content: "x" }], schema }),
      Error,
      "gemini_http_500",
    );
  } finally { globalThis.fetch = original; }
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/gemini_test.ts`
Expected: FAIL — `gemini.ts` does not exist.

- [ ] **Step 3: Create `_shared/ai/gemini.ts`**

```ts
import { NeutralSchema, toGeminiSchema } from "./schema.ts";
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
    return `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`;
  }

  private async post(body: unknown, signal: AbortSignal): Promise<GeminiResponse> {
    const res = await fetch(this.url(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
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

      let calls = 0;
      while (calls < maxCalls) {
        const data = await this.post({
          system_instruction: systemInstruction,
          contents,
          tools: [toolDecl],
          tool_config: { function_calling_config: { mode: "AUTO" } },
          generationConfig: { temperature },
        }, controller.signal);
        const parts = data.candidates?.[0]?.content?.parts ?? [];
        const fnPart = parts.find((p) => p.functionCall);
        if (!fnPart?.functionCall) break;
        const { name, args } = fnPart.functionCall;
        const result = await opts.executeTool(name, args ?? {});
        contents.push({ role: "model", parts: [{ functionCall: fnPart.functionCall }] });
        contents.push({
          role: "user",
          parts: [{ functionResponse: { name, response: { result } } }],
        });
        calls++;
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/gemini_test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/ai/gemini.ts supabase/functions/_shared/ai/gemini_test.ts
git commit -m "feat(ai): GeminiProvider (generateJson + runToolLoop)"
```

---

## Task 3: OpenAiProvider

**Files:**
- Create: `supabase/functions/_shared/ai/openai.ts`
- Test: `supabase/functions/_shared/ai/openai_test.ts`

- [ ] **Step 1: Write the failing tests `_shared/ai/openai_test.ts`**

```ts
import { assertEquals, assertRejects } from "jsr:@std/assert";
import { OpenAiProvider } from "./openai.ts";
import type { NeutralSchema } from "./schema.ts";

const schema: NeutralSchema = {
  type: "object",
  properties: { answer: { type: "string" } },
  required: ["answer"],
};

interface Captured { url: string; body: Record<string, unknown>; headers: Record<string, string>; }

function stubFetch(responses: unknown[]): { calls: Captured[]; restore: () => void } {
  const original = globalThis.fetch;
  const calls: Captured[] = [];
  let i = 0;
  globalThis.fetch = ((url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: String(url),
      body: JSON.parse(String(init?.body ?? "{}")),
      headers: (init?.headers ?? {}) as Record<string, string>,
    });
    const payload = responses[Math.min(i, responses.length - 1)];
    i++;
    return Promise.resolve(new Response(JSON.stringify(payload), { status: 200 }));
  }) as typeof fetch;
  return { calls, restore: () => { globalThis.fetch = original; } };
}

function openaiContent(obj: unknown) {
  return { choices: [{ message: { role: "assistant", content: JSON.stringify(obj) } }] };
}

Deno.test("generateJson posts chat/completions with strict json_schema and parses content", async () => {
  const { calls, restore } = stubFetch([openaiContent({ answer: "hi" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    const out = await p.generateJson<{ answer: string }>({
      system: "sys",
      messages: [{ role: "user", content: "hello" }],
      schema,
      temperature: 0.2,
    });
    assertEquals(out.answer, "hi");
    assertEquals(calls[0].url, "https://api.openai.com/v1/chat/completions");
    assertEquals(calls[0].headers.Authorization, "Bearer KEY");
    const body = calls[0].body;
    assertEquals(body.model, "gpt-4o-mini");
    assertEquals(body.temperature, 0.2);
    const rf = body.response_format as Record<string, Record<string, unknown>>;
    assertEquals(rf.type, "json_schema");
    assertEquals(rf.json_schema.strict, true);
    const msgs = body.messages as Array<{ role: string; content: unknown }>;
    assertEquals(msgs[0].role, "system");
    assertEquals(msgs[1].role, "user");
  } finally { restore(); }
});

Deno.test("generateJson sends an image as a data URL in the user message content", async () => {
  const { calls, restore } = stubFetch([openaiContent({ answer: "ok" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    await p.generateJson({
      messages: [{ role: "user", content: "read" }],
      schema,
      image: { mimeType: "image/png", dataBase64: "AAAA" },
    });
    const msgs = calls[0].body.messages as Array<{ role: string; content: Array<Record<string, unknown>> }>;
    const parts = msgs[msgs.length - 1].content;
    assertEquals(parts[0].type, "text");
    assertEquals(parts[1].type, "image_url");
    assertEquals(
      (parts[1].image_url as Record<string, string>).url,
      "data:image/png;base64,AAAA",
    );
  } finally { restore(); }
});

Deno.test("runToolLoop handles tool_calls, appends tool messages, then a final structured call", async () => {
  const execed: string[] = [];
  const toolTurn = {
    choices: [{
      message: {
        role: "assistant",
        content: null,
        tool_calls: [{ id: "call_1", type: "function", function: { name: "pipeline_stats", arguments: "{}" } }],
      },
    }],
  };
  const { calls, restore } = stubFetch([toolTurn, openaiContent({ answer: "done" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    const out = await p.runToolLoop<{ answer: string }>({
      system: "sys",
      messages: [{ role: "user", content: "stats?" }],
      tools: [{ name: "pipeline_stats", description: "d", parameters: { type: "object" } }],
      finalSchema: schema,
      executeTool: (name) => { execed.push(name); return Promise.resolve({ leads: 3 }); },
    });
    assertEquals(out.answer, "done");
    assertEquals(execed, ["pipeline_stats"]);
    // Final call: has response_format, no tools.
    const finalBody = calls[1].body;
    assertEquals("response_format" in finalBody, true);
    const finalMsgs = finalBody.messages as Array<{ role: string; tool_call_id?: string }>;
    // system, user, assistant(tool_calls), tool result.
    assertEquals(finalMsgs.some((m) => m.role === "tool" && m.tool_call_id === "call_1"), true);
  } finally { restore(); }
});

Deno.test("runToolLoop stops after maxToolCalls", async () => {
  let execs = 0;
  const toolTurn = {
    choices: [{ message: { role: "assistant", tool_calls: [{ id: "c", type: "function", function: { name: "t", arguments: "{}" } }] } }],
  };
  const { calls, restore } = stubFetch([toolTurn, toolTurn, toolTurn, openaiContent({ answer: "x" })]);
  try {
    const p = new OpenAiProvider("KEY", "gpt-4o-mini", 5000);
    await p.runToolLoop({
      system: "s",
      messages: [{ role: "user", content: "go" }],
      tools: [{ name: "t", description: "d", parameters: { type: "object" } }],
      finalSchema: schema,
      executeTool: () => { execs++; return Promise.resolve({}); },
      maxToolCalls: 2,
    });
    assertEquals(execs, 2);
    assertEquals(calls.length, 3); // 2 loop + 1 final
  } finally { restore(); }
});

Deno.test("generateJson throws on non-200", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response("no", { status: 401 }))) as typeof fetch;
  try {
    const p = new OpenAiProvider("KEY", "m", 5000);
    await assertRejects(
      () => p.generateJson({ messages: [{ role: "user", content: "x" }], schema }),
      Error,
      "openai_http_401",
    );
  } finally { globalThis.fetch = original; }
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/openai_test.ts`
Expected: FAIL — `openai.ts` does not exist.

- [ ] **Step 3: Create `_shared/ai/openai.ts`**

```ts
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
      if (opts.image && messages.length > 0) {
        const last = messages[messages.length - 1] as { role: string; content: string };
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
        messages.push(msg as Record<string, unknown>);
        for (const tc of toolCalls) {
          let args: Record<string, unknown> = {};
          try {
            args = JSON.parse(tc.function.arguments || "{}") as Record<string, unknown>;
          } catch {
            args = {};
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/openai_test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/ai/openai.ts supabase/functions/_shared/ai/openai_test.ts
git commit -m "feat(ai): OpenAiProvider (generateJson + runToolLoop)"
```

---

## Task 4: Provider factory

**Files:**
- Create: `supabase/functions/_shared/ai/factory.ts`
- Test: `supabase/functions/_shared/ai/factory_test.ts`

- [ ] **Step 1: Write the failing tests `_shared/ai/factory_test.ts`**

```ts
import { assertEquals, assertInstanceOf, assertThrows } from "jsr:@std/assert";
import { createProvider } from "./factory.ts";
import { GeminiProvider } from "./gemini.ts";
import { OpenAiProvider } from "./openai.ts";

const ENV_KEYS = [
  "AI_PROVIDER",
  "AI_PROVIDER_ASSISTANT",
  "AI_PROVIDER_PARSE_ENQUIRY",
  "GEMINI_API_KEY",
  "OPENAI_API_KEY",
  "OPENAI_MODEL",
];
function clearEnv() { for (const k of ENV_KEYS) Deno.env.delete(k); }

Deno.test("defaults to gemini when nothing is set", () => {
  clearEnv();
  Deno.env.set("GEMINI_API_KEY", "g");
  assertInstanceOf(createProvider("assistant"), GeminiProvider);
});

Deno.test("global AI_PROVIDER selects openai", () => {
  clearEnv();
  Deno.env.set("AI_PROVIDER", "openai");
  Deno.env.set("OPENAI_API_KEY", "o");
  assertInstanceOf(createProvider("draft-reply"), OpenAiProvider);
});

Deno.test("per-function override beats global", () => {
  clearEnv();
  Deno.env.set("AI_PROVIDER", "gemini");
  Deno.env.set("GEMINI_API_KEY", "g");
  Deno.env.set("AI_PROVIDER_PARSE_ENQUIRY", "openai");
  Deno.env.set("OPENAI_API_KEY", "o");
  assertInstanceOf(createProvider("parse-enquiry"), OpenAiProvider);
  // A different function still uses the global default.
  assertInstanceOf(createProvider("assistant"), GeminiProvider);
});

Deno.test("missing key throws a labelled error", () => {
  clearEnv();
  Deno.env.set("AI_PROVIDER", "openai");
  assertThrows(() => createProvider("assistant"), Error, "missing_openai_key");
});

Deno.test("unknown provider throws", () => {
  clearEnv();
  Deno.env.set("AI_PROVIDER", "llama");
  assertThrows(() => createProvider("assistant"), Error, "unsupported_provider_llama");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/factory_test.ts`
Expected: FAIL — `factory.ts` does not exist.

- [ ] **Step 3: Create `_shared/ai/factory.ts`**

```ts
import { GeminiProvider } from "./gemini.ts";
import { OpenAiProvider } from "./openai.ts";
import type { LlmProvider } from "./types.ts";

/** Resolve and construct the LLM provider for edge function [fn].
 * Precedence: AI_PROVIDER_<FN> > AI_PROVIDER > "gemini". */
export function createProvider(fn: string): LlmProvider {
  const overrideKey = `AI_PROVIDER_${fn.toUpperCase().replace(/-/g, "_")}`;
  const name = Deno.env.get(overrideKey) ?? Deno.env.get("AI_PROVIDER") ?? "gemini";
  const timeoutMs = Number(Deno.env.get("AI_TIMEOUT_MS") ?? "15000");

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/factory_test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/ai/factory.ts supabase/functions/_shared/ai/factory_test.ts
git commit -m "feat(ai): createProvider factory with per-function override"
```

---

## Task 5: Prompt Manager modules

Move each function's prompt builder + response schema (rewritten as `NeutralSchema`) + tool defs into `_shared/ai/prompts/`. **Copy the prompt-string bodies verbatim** from the named source files — only the wrapping (export names, schema shape) changes.

**Files:**
- Create: `supabase/functions/_shared/ai/prompts/assistant.ts`
- Create: `supabase/functions/_shared/ai/prompts/work-items.ts`
- Create: `supabase/functions/_shared/ai/prompts/draft-reply.ts`
- Create: `supabase/functions/_shared/ai/prompts/summarize-customer.ts`
- Create: `supabase/functions/_shared/ai/prompts/parse-enquiry.ts`

- [ ] **Step 1: Create `_shared/ai/prompts/assistant.ts`**

`assistantSystemPrompt` body is copied verbatim from `supabase/functions/assistant/schema.ts:117-128`. Tools and final schema are rewritten as neutral (`LlmTool[]` / `NeutralSchema`).

```ts
import type { NeutralSchema } from "../schema.ts";
import type { LlmTool } from "../types.ts";

export const assistantTools: LlmTool[] = [
  {
    name: "outstanding_summary",
    description:
      "Returns a list of customers with outstanding (unpaid) amounts. Call this when asked about pending payments, money owed, or collections.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "integer", description: "Max customers to return (default 10, max 20)" },
      },
    },
  },
  {
    name: "top_customers",
    description:
      "Returns the seller's top customers ranked by lifetime value. Call this for questions about best customers, highest revenue accounts, or repeat buyers.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "integer", description: "Max customers to return (default 10, max 20)" },
      },
    },
  },
  {
    name: "pipeline_stats",
    description:
      "Returns aggregate business stats: total leads, open leads, total orders, active orders, total revenue, outstanding payments, paid this month, total customers. Call this for overview questions about the business.",
    parameters: { type: "object", properties: {} },
  },
  {
    name: "overdue_followups",
    description:
      "Returns follow-ups that are past their due date and not yet completed. Call this when asked about missed follow-ups, overdue tasks, or customers to contact.",
    parameters: {
      type: "object",
      properties: {
        limit: { type: "integer", description: "Max follow-ups to return (default 10, max 20)" },
      },
    },
  },
];

export const assistantFinalSchema: NeutralSchema = {
  type: "object",
  properties: {
    answer: {
      type: "string",
      description:
        "A concise, business-focused answer. No amounts, UPI IDs, or phone numbers — these come from the database, not from you. Reference customer names and factual info from the tool results.",
    },
    suggestions: {
      type: "array",
      items: { type: "string" },
      description: "2-4 short follow-up questions the seller might want to ask next.",
    },
    proposed_work_items: {
      type: "array",
      description:
        "Work items to propose only when the user explicitly asks to create reminders or follow-ups. Empty otherwise.",
      items: {
        type: "object",
        properties: {
          kind: {
            type: "string",
            enum: ["payment_reminder", "reply", "follow_up", "create_order", "invoice"],
          },
          customer_id: { type: "string" },
          customer_name: { type: "string" },
          draft_message: {
            type: "string",
            description:
              "A short, polite message draft. MUST NOT contain phone numbers, UPI IDs, or exact rupee amounts.",
          },
          priority: { type: "string", enum: ["high", "medium", "low"] },
        },
        required: ["kind", "customer_id", "customer_name", "draft_message", "priority"],
      },
    },
  },
  required: ["answer", "suggestions", "proposed_work_items"],
};

export function assistantSystemPrompt(sellerName: string): string {
  return `You are the Closr AI assistant helping ${sellerName} manage their sales business.

You have access to read-only tools that fetch live data from the database. Use them to answer the seller's questions accurately.

CRITICAL RULES:
1. Never include phone numbers, UPI IDs, or Paytm/GPay handles in your answer or draft messages.
2. Never include exact rupee amounts in draft messages — refer to "the pending amount" or "the outstanding balance" instead.
3. Only propose work items (reminders, follow-ups) when the seller explicitly asks you to create them.
4. Keep answers concise and actionable. Reference actual customer names from tool results.
5. You are a business assistant, not a general chatbot. Stay focused on sales, payments, customers, and follow-ups.`;
}

// PII guard: reject proposed items whose draft_message leaks sensitive data.
export const PII_PATTERN = /₹|\d{10}|upi|@[a-z]|paytm|gpay|phonepe/i;
```

- [ ] **Step 2: Create `_shared/ai/prompts/work-items.ts`**

Move `CustomerSignal`, `GenerateInput`, `buildPrompt`→`workItemsPrompt` (verbatim body from `generate-work-items/schema.ts:86-129`), and `responseSchema`→`workItemsSchema` (as neutral).

```ts
import type { NeutralSchema } from "../schema.ts";

export interface CustomerSignal {
  customerId: string;
  customerName: string;
  lastMessage: string | null;
  lastMessageDirection: string | null;
  daysSinceLastMessage: number | null;
  hasUnpaidOrder: boolean;
  followUpOverdueDays: number | null;
  leadIntent: string | null;
  leadMessage: string | null;
}

export interface GenerateInput {
  signals: CustomerSignal[];
  sellerName: string;
}

export const workItemsSchema: NeutralSchema = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          customerId: { type: "string" },
          kind: {
            type: "string",
            enum: ["payment_reminder", "reply", "create_order", "invoice", "follow_up", "share_catalog"],
          },
          priority: { type: "string", enum: ["high", "medium", "low"] },
          score: { type: "integer" },
          title: { type: "string" },
          context: { type: "string" },
          draftMessage: { type: "string" },
          confidence: { type: "number" },
        },
        required: ["customerId", "kind", "priority", "score", "title", "context", "draftMessage", "confidence"],
      },
    },
  },
  required: ["items"],
};

export function workItemsPrompt(input: GenerateInput): string {
  const signalLines = input.signals.map((s, i) => {
    const parts = [`${i + 1}. Customer ID: ${s.customerId}`, `   Name: ${s.customerName}`];
    if (s.lastMessage) {
      parts.push(`   Last message (${s.lastMessageDirection}): "${s.lastMessage.slice(0, 120)}"`);
    }
    if (s.daysSinceLastMessage !== null) {
      parts.push(`   Days since last contact: ${s.daysSinceLastMessage}`);
    }
    if (s.hasUnpaidOrder) {
      parts.push("   Has unpaid order: yes (amount will be added by seller — DO NOT include amounts)");
    }
    if (s.followUpOverdueDays !== null) {
      parts.push(`   Follow-up overdue by: ${s.followUpOverdueDays} day(s)`);
    }
    if (s.leadIntent) parts.push(`   Lead intent: ${s.leadIntent}`);
    if (s.leadMessage) parts.push(`   Lead context: "${s.leadMessage.slice(0, 100)}"`);
    return parts.join("\n");
  });

  return [
    `You are an AI sales assistant helping Indian seller "${input.sellerName}" prioritize their work.`,
    "For each customer signal below, decide what action is most important right now.",
    "",
    "CRITICAL RULES:",
    "- NEVER include rupee amounts, UPI IDs, bank account numbers, or phone numbers in ANY field.",
    "- draftMessage must be prose only — seller will add payment details from their records.",
    "- score: 0–100 (higher = more urgent). high priority = score 70+, medium = 40–69, low = below 40.",
    "- title: short action label for the seller (e.g., 'Payment due from Priya', 'Follow up with Rahul').",
    "- context: one-line reason why this action matters now.",
    "- draftMessage: a WhatsApp-ready draft in natural Indian business tone, under 60 words.",
    "- Only return items that genuinely need action. Skip customers who seem fine.",
    "- At most 20 items total.",
    "",
    "Customer signals:",
    ...signalLines,
    "",
    "Return JSON matching the schema.",
  ].join("\n");
}
```

- [ ] **Step 3: Create `_shared/ai/prompts/draft-reply.ts`**

Move `DraftObjective`, `DraftInput`, `buildPrompt`→`draftReplyPrompt` (verbatim body from `draft-reply/schema.ts:30-68`), `responseSchema`→`draftReplySchema` (neutral).

```ts
import type { NeutralSchema } from "../schema.ts";

export type DraftObjective = "reply" | "payment_reminder" | "follow_up" | "nudge";

export interface DraftInput {
  customerId: string;
  objective: DraftObjective;
  messages: { direction: string; body: string }[];
  customerName: string | null;
  outstandingAmount: number | null;
  enquiryContext: string | null;
}

export const draftReplySchema: NeutralSchema = {
  type: "object",
  properties: {
    message: { type: "string" },
    confidence: { type: "number" },
  },
  required: ["message", "confidence"],
};

export function draftReplyPrompt(input: DraftInput, sellerName: string): string {
  const lastMessages = input.messages.slice(-10);
  const chatLines = lastMessages
    .map((m) => `${m.direction === "inbound" ? "Customer" : "You"}: ${m.body}`)
    .join("\n");

  const objectiveInstructions: Record<DraftObjective, string> = {
    reply:
      "Write a warm, concise reply to the customer's latest message. Match the seller's conversational tone.",
    payment_reminder:
      "Write a polite payment reminder. Do NOT include any rupee amounts, UPI IDs, or account numbers in the message — those will be added by the seller from their records.",
    follow_up: "Write a friendly follow-up message to re-engage the customer.",
    nudge: "Write a short nudge to prompt the customer to respond.",
  };

  return [
    `You are drafting a WhatsApp message for an Indian seller named ${sellerName}.`,
    "Write in a friendly, natural Indian business tone (mix of English and simple Hindi is fine if appropriate).",
    "",
    "CRITICAL RULES:",
    "- NEVER include specific rupee amounts, UPI IDs, bank account numbers, or phone numbers in the message.",
    "- NEVER invent product details, prices, or order information not in the conversation.",
    "- Write prose only — the seller will add specific amounts from their records.",
    "- Keep it under 80 words.",
    "",
    `Objective: ${objectiveInstructions[input.objective]}`,
    "",
    "Recent conversation:",
    chatLines || "(No messages yet)",
    "",
    input.enquiryContext ? `Context: ${input.enquiryContext}` : "",
    "",
    "Return JSON with 'message' (the draft text) and 'confidence' (0..1, your confidence in the draft quality).",
  ].filter(Boolean).join("\n");
}
```

- [ ] **Step 4: Create `_shared/ai/prompts/summarize-customer.ts`**

Move `SummarizeInput`, `buildPrompt`→`summarizePrompt` (verbatim body from `summarize-customer/schema.ts:36-60`), `responseSchema`→`summarizeSchema` (neutral).

```ts
import type { NeutralSchema } from "../schema.ts";

export interface SummarizeInput {
  customerName: string | null;
  messages: { direction: string; body: string; id: string }[];
  existingFacts: { fact: string }[];
}

export const summarizeSchema: NeutralSchema = {
  type: "object",
  properties: {
    bullets: { type: "array", items: { type: "string" } },
    close_confidence: { type: "number" },
    facts: {
      type: "array",
      items: {
        type: "object",
        properties: {
          fact: { type: "string" },
          source_message_id: { type: "string" },
        },
        required: ["fact", "source_message_id"],
      },
    },
  },
  required: ["bullets", "close_confidence", "facts"],
};

export function summarizePrompt(input: SummarizeInput): string {
  const chatLines = input.messages
    .map((m) => `[${m.id}] ${m.direction === "inbound" ? "Customer" : "Seller"}: ${m.body}`)
    .join("\n");

  return [
    "You summarize a seller-customer WhatsApp conversation for an Indian social-commerce seller.",
    "",
    "CRITICAL RULES:",
    "- NEVER include rupee amounts, phone numbers, UPI IDs, or payment details in your output.",
    "- Bullets describe the customer's interests, preferences, and intent — not financial specifics.",
    "- facts are standalone insights useful for future interactions (preferences, occasions, tone).",
    "- Source_message_id must be an exact ID from the conversation below.",
    "",
    `Customer name: ${input.customerName ?? "Unknown"}`,
    "",
    "Conversation (format: [message_id] Sender: body):",
    chatLines || "(No messages)",
    "",
    "Return JSON with:",
    "- bullets: 2-5 short bullet points summarising this customer's interests and status",
    "- close_confidence: 0..1 probability this lead will convert to an order soon",
    "- facts: reusable facts about the customer (max 5, only novel ones not already known)",
  ].join("\n");
}
```

- [ ] **Step 5: Create `_shared/ai/prompts/parse-enquiry.ts`**

Move `buildPrompt`→`parseEnquiryPrompt` (verbatim body from `parse-enquiry/schema.ts:46-72`), `responseSchema`→`parseEnquirySchema` (neutral, with `nullable`). The `ParsedEnquiry` output type stays in the function's `schema.ts` (Task 10).

```ts
import type { NeutralSchema } from "../schema.ts";

export const parseEnquirySchema: NeutralSchema = {
  type: "object",
  properties: {
    customer_name: { type: "string", nullable: true },
    phone: { type: "string", nullable: true },
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          qty: { type: "integer" },
          price: { type: "number", nullable: true },
        },
        required: ["name", "qty"],
      },
    },
    intent: { type: "string", enum: ["inquiry", "order", "follow_up"] },
    follow_up_date: { type: "string", nullable: true },
    type: { type: "string", enum: ["enquiry", "order"] },
    confidence: { type: "number" },
    budget: { type: "number", nullable: true },
    notes: { type: "string", nullable: true },
  },
  required: ["items", "intent", "type", "confidence"],
};

export function parseEnquiryPrompt(text: string, todayIso: string): string {
  const hasText = text.trim().length > 0;
  return [
    "You extract structured sales-lead data from an Indian social-commerce",
    "seller's chat or spoken note. An image, if attached, is a screenshot of a",
    "chat — read the messages in it. Return ONLY data that is present or",
    "clearly implied. Use null when unsure; never invent a phone number or name.",
    "",
    "Rules:",
    "- phone: 10-digit Indian mobile if present, digits only, no country code.",
    "- items: product/qty pairs the customer wants; qty defaults to 1; price in",
    "  rupees as a number when stated, else null.",
    "- intent: 'order' if they are committing/booking/paying; 'follow_up' if they",
    "  want to be contacted later; otherwise 'inquiry'.",
    "- type: 'order' only when intent is 'order' AND there is at least one item;",
    "  otherwise 'enquiry'.",
    `- follow_up_date: absolute date (YYYY-MM-DD) resolved from today (${todayIso})`,
    "  when they mention a time like 'tomorrow'/'next week'; else null.",
    "- confidence: your overall 0..1 confidence in this extraction.",
    "- budget: the customer's stated maximum spend in rupees as a number, or null.",
    "- notes: any seller-useful context not captured elsewhere (e.g. colour preference,",
    "  delivery constraint, occasion); one short sentence or null.",
    "",
    hasText ? "Message:" : "Extract from the attached screenshot.",
    hasText ? text : "",
  ].join("\n");
}
```

- [ ] **Step 6: Typecheck the prompt modules**

Run: `cd supabase/functions && deno check _shared/ai/prompts/*.ts`
Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/_shared/ai/prompts/
git commit -m "feat(ai): central Prompt Manager for all five functions"
```

---

## Task 6: Refactor `assistant` onto the shared provider

**Files:**
- Modify: `supabase/functions/assistant/index.ts`
- Modify: `supabase/functions/assistant/schema.ts` (reduce to input/output types only)
- Delete: `supabase/functions/assistant/provider.ts`

- [ ] **Step 1: Slim `assistant/schema.ts` to types only**

Replace the entire file with just the input/output interfaces (the tools, final schema, prompt, and PII pattern now live in `_shared/ai/prompts/assistant.ts`):

```ts
export interface AssistantInput {
  question: string;
  customer_id?: string;
  history?: Array<{ role: string; content: string }>;
}

export interface ProposedWorkItem {
  kind: string;
  customer_id: string;
  customer_name: string;
  draft_message: string;
  priority: "high" | "medium" | "low";
}

export interface AssistantOutput {
  answer: string;
  suggestions: string[];
  proposed_work_items: ProposedWorkItem[];
}
```

- [ ] **Step 2: Delete the old provider**

```bash
git rm supabase/functions/assistant/provider.ts
```

- [ ] **Step 3: Rewrite the LLM section of `assistant/index.ts`**

Replace the import of `createAssistantProvider` (line 3) with:

```ts
import { createProvider } from "../_shared/ai/factory.ts";
import {
  assistantFinalSchema,
  assistantSystemPrompt,
  assistantTools,
  PII_PATTERN,
} from "../_shared/ai/prompts/assistant.ts";
```

Also widen the existing type import on line 4 so `AssistantOutput` is available for `runToolLoop<AssistantOutput>`:

```ts
import type { AssistantInput, AssistantOutput } from "./schema.ts";
```

Replace the `try { const provider = createAssistantProvider(); const output = await provider.answer(...); ... }` block (the `startMs` try/catch, lines 71-97) with a version that uses `runToolLoop` and keeps the same telemetry, PII filtering, and error mapping:

```ts
  const startMs = Date.now();
  try {
    const provider = createProvider("assistant");
    const output = await provider.runToolLoop<AssistantOutput>({
      system: assistantSystemPrompt(sellerName),
      messages: [...history.map((h) => ({
        role: h.role === "assistant" ? "assistant" as const : "user" as const,
        content: h.content,
      })), { role: "user", content: question }],
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
```

Keep everything else in the file unchanged (auth, rate limit, validation, seller-name fetch, telemetry insert for `assistant_query`).

- [ ] **Step 4: Typecheck**

Run: `cd supabase/functions && deno check assistant/index.ts`
Expected: No errors. (`assistant/provider.ts` and `assistant/schema.ts` no longer export the moved symbols; confirm nothing else imports them: `grep -rn "createAssistantProvider\|buildSystemPrompt\|assistantTools" supabase/functions/assistant` returns nothing outside the new imports.)

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/assistant/
git commit -m "refactor(ai): assistant uses shared provider runToolLoop"
```

---

## Task 7: Refactor `generate-work-items`

**Files:**
- Modify: `supabase/functions/generate-work-items/index.ts`
- Modify: `supabase/functions/generate-work-items/schema.ts` (output types only)
- Delete: `supabase/functions/generate-work-items/provider.ts`

- [ ] **Step 1: Slim `generate-work-items/schema.ts` to types only**

Replace the file with the type definitions the handler still uses (`WorkItemKind`, `WorkItemPriority`, `WorkItemOutput`, `GenerateOutput`). `CustomerSignal`/`GenerateInput`/prompt/schema now live in `_shared/ai/prompts/work-items.ts`:

```ts
export type WorkItemKind =
  | "payment_reminder"
  | "reply"
  | "create_order"
  | "invoice"
  | "follow_up"
  | "share_catalog";

export type WorkItemPriority = "high" | "medium" | "low";

export interface WorkItemOutput {
  customerId: string;
  kind: WorkItemKind;
  priority: WorkItemPriority;
  score: number;
  title: string;
  context: string;
  draftMessage: string;
  confidence: number;
}

export interface GenerateOutput {
  items: WorkItemOutput[];
}
```

- [ ] **Step 2: Delete the old provider**

```bash
git rm supabase/functions/generate-work-items/provider.ts
```

- [ ] **Step 3: Update imports + the LLM call in `generate-work-items/index.ts`**

Change the imports (lines 3-4) to:

```ts
import { createProvider } from "../_shared/ai/factory.ts";
import { CustomerSignal, workItemsPrompt, workItemsSchema } from "../_shared/ai/prompts/work-items.ts";
import { GenerateOutput, WorkItemKind, WorkItemPriority } from "./schema.ts";
```

Replace the `rawItems` declaration + provider call block (lines 178-190) with:

```ts
  let rawItems: GenerateOutput["items"];
  try {
    const provider = createProvider("generate-work-items");
    const result = await provider.generateJson<GenerateOutput>({
      messages: [{ role: "user", content: workItemsPrompt({ signals, sellerName: bizRow?.name ?? "Seller" }) }],
      schema: workItemsSchema,
      temperature: 0.3,
    });
    rawItems = result.items ?? [];
  } catch (e) {
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`generate_work_items_failed:${label}`);
    return json({ error: "generate_failed" }, 502);
  }
```

Everything else (signal gathering, validation, PII reject, insert) is unchanged.

- [ ] **Step 4: Typecheck**

Run: `cd supabase/functions && deno check generate-work-items/index.ts`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/generate-work-items/
git commit -m "refactor(ai): generate-work-items uses shared provider generateJson"
```

---

## Task 8: Refactor `draft-reply`

**Files:**
- Modify: `supabase/functions/draft-reply/index.ts`
- Delete: `supabase/functions/draft-reply/schema.ts`
- Delete: `supabase/functions/draft-reply/provider.ts`

- [ ] **Step 1: Delete the old provider and schema (both fully moved)**

```bash
git rm supabase/functions/draft-reply/provider.ts supabase/functions/draft-reply/schema.ts
```

- [ ] **Step 2: Update `draft-reply/index.ts`**

Replace the `createDraftProvider` import (line 3) with:

```ts
import { createProvider } from "../_shared/ai/factory.ts";
import { DraftInput, draftReplyPrompt, draftReplySchema } from "../_shared/ai/prompts/draft-reply.ts";
```

Replace the `try { const provider = createDraftProvider(); const result = await provider.generate(...); ... }` block (lines 94-115) with:

```ts
  try {
    const provider = createProvider("draft-reply");
    const input: DraftInput = {
      customerId,
      objective: objective as DraftInput["objective"],
      messages,
      customerName: customerRow?.name ?? null,
      outstandingAmount: null, // never from model; client reads from DB
      enquiryContext: leadRow?.message ?? null,
    };
    const result = await provider.generateJson<{ message: string; confidence: number }>({
      messages: [{ role: "user", content: draftReplyPrompt(input, bizRow?.name ?? "Seller") }],
      schema: draftReplySchema,
      temperature: 0.4,
    });
    const confidence = Math.min(1, Math.max(0, result.confidence));
    return json({ message: result.message, confidence }, 200);
  } catch (e) {
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`draft_reply_failed:${label}`);
    return json({ error: "draft_failed" }, 502);
  }
```

- [ ] **Step 3: Typecheck**

Run: `cd supabase/functions && deno check draft-reply/index.ts`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/draft-reply/
git commit -m "refactor(ai): draft-reply uses shared provider generateJson"
```

---

## Task 9: Refactor `summarize-customer`

**Files:**
- Modify: `supabase/functions/summarize-customer/index.ts`
- Delete: `supabase/functions/summarize-customer/schema.ts`
- Delete: `supabase/functions/summarize-customer/provider.ts`

- [ ] **Step 1: Delete the old provider and schema**

```bash
git rm supabase/functions/summarize-customer/provider.ts supabase/functions/summarize-customer/schema.ts
```

- [ ] **Step 2: Update `summarize-customer/index.ts`**

Replace the `createSummarizeProvider` import (line 3) with:

```ts
import { createProvider } from "../_shared/ai/factory.ts";
import { summarizePrompt, summarizeSchema } from "../_shared/ai/prompts/summarize-customer.ts";
```

Replace the `const provider = createSummarizeProvider(); const result = await provider.summarize({...});` call (lines 97-102) with:

```ts
    const provider = createProvider("summarize-customer");
    const result = await provider.generateJson<{
      bullets: string[];
      close_confidence: number;
      facts: { fact: string; source_message_id: string }[];
    }>({
      messages: [{
        role: "user",
        content: summarizePrompt({
          customerName: customerRow?.name ?? null,
          messages,
          existingFacts,
        }),
      }],
      schema: summarizeSchema,
      temperature: 0.2,
    });
```

The rest of the `try` block (confidence clamp, `ai_summaries` upsert, facts merge, response) is unchanged.

- [ ] **Step 3: Typecheck**

Run: `cd supabase/functions && deno check summarize-customer/index.ts`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/summarize-customer/
git commit -m "refactor(ai): summarize-customer uses shared provider generateJson"
```

---

## Task 10: Refactor `parse-enquiry` (multimodal)

**Files:**
- Modify: `supabase/functions/parse-enquiry/index.ts`
- Modify: `supabase/functions/parse-enquiry/schema.ts` (output type only)
- Delete: `supabase/functions/parse-enquiry/provider.ts`

- [ ] **Step 1: Slim `parse-enquiry/schema.ts` to the output type**

Replace the file with just the `ParsedEnquiry` output interface (prompt + schema moved to `_shared/ai/prompts/parse-enquiry.ts`):

```ts
export interface ParsedEnquiry {
  customer_name: string | null;
  phone: string | null;
  items: { name: string; qty: number; price: number | null }[];
  intent: "inquiry" | "order" | "follow_up";
  follow_up_date: string | null;
  type: "enquiry" | "order";
  confidence: number;
  budget: number | null;
  notes: string | null;
}
```

- [ ] **Step 2: Delete the old provider**

```bash
git rm supabase/functions/parse-enquiry/provider.ts
```

- [ ] **Step 3: Update `parse-enquiry/index.ts`**

Replace the `createParser` import (line 3) with:

```ts
import { createProvider } from "../_shared/ai/factory.ts";
import { parseEnquiryPrompt, parseEnquirySchema } from "../_shared/ai/prompts/parse-enquiry.ts";
import { ParsedEnquiry } from "./schema.ts";
```

Replace the final `try { const parser = createParser(); const result = await parser.parse({ text, image }); return json(result, 200); } catch ...` block (lines 86-95) with a version that builds the prompt, resolves today, and passes the image through `generateJson`:

```ts
  try {
    const today = new Date().toISOString().slice(0, 10);
    const provider = createProvider("parse-enquiry");
    const result = await provider.generateJson<ParsedEnquiry>({
      messages: [{ role: "user", content: parseEnquiryPrompt(text, today) }],
      schema: parseEnquirySchema,
      temperature: 0,
      image: image ? { mimeType: image.mimeType, dataBase64: image.data } : undefined,
    });
    return json(result, 200);
  } catch (e) {
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`parse_failed:${label}`);
    return json({ error: "parse_failed" }, 502);
  }
```

Note: the local `image` variable is `{ mimeType: string; data: string } | undefined` (built earlier in the handler). Map its `.data` to the provider's `dataBase64`.

- [ ] **Step 4: Typecheck**

Run: `cd supabase/functions && deno check parse-enquiry/index.ts`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/parse-enquiry/
git commit -m "refactor(ai): parse-enquiry uses shared provider generateJson (multimodal)"
```

---

## Task 11: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole AI unit suite**

Run: `cd supabase/functions && deno test --allow-env _shared/ai/`
Expected: All tests pass (schema 3 + gemini 5 + openai 5 + factory 5 = 18).

- [ ] **Step 2: Typecheck every function**

Run: `cd supabase/functions && deno check **/*.ts`
Expected: No errors. If any function still imports a deleted symbol, fix the import.

- [ ] **Step 3: Confirm no stale references remain**

Run:
```bash
grep -rn "createAssistantProvider\|createWorkItemsProvider\|createDraftProvider\|createSummarizeProvider\|createParser\|unsupported_provider_" supabase/functions --include=*.ts | grep -v "_shared/ai/factory.ts"
```
Expected: no matches (the only `unsupported_provider_` is now in `factory.ts`; all per-function `create*Provider` are gone).

- [ ] **Step 4: Confirm all five `provider.ts` are deleted**

Run: `ls supabase/functions/*/provider.ts 2>/dev/null || echo "none remain"`
Expected: `none remain`.

- [ ] **Step 5: Commit any verification fixes**

```bash
git add -A
git commit -m "chore(ai): verify shared provider abstraction (deno test + check green)"
```

(Skip if steps 1-4 produced no changes.)

---

## Self-Review notes (author)

- **Spec coverage:** provider abstraction (Gemini+OpenAI, both capabilities) → Tasks 2-3; neutral schema + translators → Task 1; factory with per-function override → Task 4; Prompt Manager → Task 5; refactor all five functions + delete provider.ts → Tasks 6-10; full-parity incl. assistant tool loop → Task 6 via `runToolLoop`; multimodal parse-enquiry → Task 10; Deno tests + `deno check` → Tasks 1-4, 11. Behavior parity (temperatures, default gemini, PII filter, tool RPCs) preserved in the refactors.
- **Type consistency:** `LlmProvider.generateJson/runToolLoop`, `NeutralSchema`, `GenerateJsonOpts/ToolLoopOpts`, `LlmTool`, `LlmImage`, `createProvider(fn)`, and every prompt/schema export name are used identically across tasks.
- **Deviations from spec, intentional:** (1) per-function request timeouts unify to a single `AI_TIMEOUT_MS` (default 15000) — lengthens parse/draft/summarize, noted. (2) Prompt Manager is a `prompts/` directory (one focused file per function) rather than a single file, for focus and to keep each function's prompt independently editable. (3) `draft-reply`/`summarize-customer`/`parse-enquiry` prompt-input types move into their prompt module; the function's `schema.ts` keeps only the output type (draft-reply/summarize keep none, so their `schema.ts` is deleted).
