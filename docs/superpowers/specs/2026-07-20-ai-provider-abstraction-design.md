# AI Provider Abstraction + Prompt Manager — Design

**Date:** 2026-07-20
**Branch:** `feat/ai-provider-abstraction`
**Status:** Approved (design), pending spec review

## Context

This is **sub-project 1 of 5** in evolving Closr AI into a production AI Business
Copilot. The larger effort decomposes into: (1) **this** — provider abstraction +
prompt manager; (2) business-context expansion (more assistant tools); (3) chat UX
overhaul (streaming, markdown, memory, retry); (4) AI Brief personalization; (5)
app-wide AI touchpoints. Sub-projects 2–5 depend on this foundation and are out of
scope here.

### Current architecture (as-is)

Closr AI runs entirely in **Supabase edge functions (Deno/TypeScript)**. Five AI
functions:

- **`assistant`** — the Closr AI chat. Gemini function-calling in two phases: a tool
  loop (≤3 calls over four read-only RPCs — `assistant_outstanding_summary`,
  `assistant_top_customers`, `assistant_pipeline_stats`, `assistant_overdue_followups`)
  followed by a structured JSON response `{answer, suggestions, proposed_work_items}`.
  Rate-limited (40/hr via `check_ai_rate_limit`), PII-guarded, telemetered to
  `app_events`.
- **`generate-work-items`** — turns per-customer signals into `AiWorkItem`s. Single-shot
  structured JSON.
- **`draft-reply`**, **`summarize-customer`**, **`parse-enquiry`** — single-shot
  structured JSON point features.

Each function carries its **own** `provider.ts` (60–190 lines) plus a `schema.ts` that
holds its TS interfaces, its prompt builder, and its Gemini response schema.

### Weaknesses this sub-project fixes

1. **No real provider abstraction.** Provider-selection logic (`AI_PROVIDER` env, default
   `gemini`) is copy-pasted into all five functions, and every one throws
   `unsupported_provider_<name>` for anything but Gemini. **OpenAI is not implemented
   anywhere** despite the product intent to support it.
2. **Prompts scattered** across five `schema.ts` files — no single Prompt Manager, no
   shared voice or one place to tune them.
3. **Duplication.** Five near-identical Gemini `fetch` implementations, five identical
   factory blocks, five timeout/abort setups.

## Scope

**In scope**

- A shared LLM provider abstraction under `supabase/functions/_shared/ai/` supporting
  **both Gemini and OpenAI**, with **full parity across all five functions** (including
  the assistant's tool-calling loop).
- A central **Prompt Manager** holding every prompt, tool definition, and response
  schema, consumed by all five functions.
- Refactor all five functions onto the shared abstraction; delete the five per-function
  `provider.ts` files.
- Deno-based unit tests for the pure adapter logic + `deno check` typechecking.

**Out of scope**

- No new AI features, tools, or context sources (sub-project 2).
- No frontend/Flutter changes (chat UX is sub-project 3).
- No streaming (sub-project 3).
- No AI Brief changes (sub-project 4).
- Deploying the edge functions (`supabase functions deploy`) is a separate manual step,
  not a code change.

## Chosen approach — Two-capability provider interface + neutral schema (Approach A)

Model each provider as implementing two capabilities, so business logic never touches a
provider quirk:

```ts
interface LlmProvider {
  generateJson<T>(opts: GenerateJsonOpts): Promise<T>;   // single-shot structured JSON
  runToolLoop<T>(opts: ToolLoopOpts): Promise<T>;        // tool loop → structured final JSON
}
```

Schemas are authored once in a **neutral** lowercase JSON-Schema form and each provider
translates to its dialect. Timeout/abort lives inside the provider. The tool loop exists
in exactly one place per provider (not per function).

### Units

**1. `supabase/functions/_shared/ai/types.ts` — neutral types + interface**

```ts
export type LlmRole = "user" | "assistant";
export interface LlmMessage { role: LlmRole; content: string; }
export interface LlmTool { name: string; description: string; parameters: NeutralSchema; }

export interface GenerateJsonOpts {
  system?: string;
  messages: LlmMessage[];
  schema: NeutralSchema;
  temperature?: number;
}
export interface ToolLoopOpts {
  system: string;
  messages: LlmMessage[];
  tools: LlmTool[];
  finalSchema: NeutralSchema;
  executeTool: (name: string, args: Record<string, unknown>) => Promise<unknown>;
  maxToolCalls?: number;    // default 3
  temperature?: number;     // default 0.3
}
export interface LlmProvider {
  generateJson<T>(opts: GenerateJsonOpts): Promise<T>;
  runToolLoop<T>(opts: ToolLoopOpts): Promise<T>;
}
```

**2. `supabase/functions/_shared/ai/schema.ts` — neutral schema + translators (pure)**

```ts
export interface NeutralSchema {
  type: "object" | "array" | "string" | "integer" | "number" | "boolean";
  description?: string;
  properties?: Record<string, NeutralSchema>;
  items?: NeutralSchema;
  enum?: string[];
  required?: string[];
}
export function toGeminiSchema(s: NeutralSchema): unknown;  // uppercases `type` recursively
export function toOpenAiSchema(s: NeutralSchema): unknown;  // adds additionalProperties:false on objects
```

- `toGeminiSchema` recursively uppercases `type` (`object`→`OBJECT`, …) and preserves
  `properties`, `items`, `enum`, `required`, `description`.
- `toOpenAiSchema` passes the schema through as standard JSON Schema and sets
  `additionalProperties: false` on every object (required for OpenAI `strict` mode). Our
  existing output schemas already mark every property `required`, so they are
  strict-compatible.

**3. `supabase/functions/_shared/ai/gemini.ts` — `GeminiProvider`**

Config: `apiKey`, `model`, `timeoutMs`. Both methods wrap the whole operation in an
`AbortController` timeout.

- `generateJson`: POST `…/models/${model}:generateContent`, body
  `{ system_instruction, contents, generationConfig: { temperature, responseMimeType:
  "application/json", responseSchema: toGeminiSchema(schema) } }`; parse
  `candidates[0].content.parts[0].text` → `JSON.parse`.
- `runToolLoop`: reproduces the current assistant loop exactly — `tools:
  [{ function_declarations: tools.map(t => ({name, description, parameters:
  toGeminiSchema(t.parameters)})) }]`, `tool_config AUTO`; loop up to `maxToolCalls`,
  executing `executeTool` and feeding `functionResponse` back; then a final
  `generateContent` with `responseSchema: toGeminiSchema(finalSchema)`. Byte-equivalent
  to today's Gemini requests so prod behavior is preserved.

**4. `supabase/functions/_shared/ai/openai.ts` — `OpenAiProvider`**

Config: `apiKey`, `model`, `timeoutMs`, `baseUrl` (default `https://api.openai.com/v1`).

- `generateJson`: POST `/chat/completions`, `messages: [{role:"system",content:system},
  ...messages]`, `response_format: { type:"json_schema", json_schema: { name:"result",
  schema: toOpenAiSchema(schema), strict:true } }`, `temperature`; parse
  `choices[0].message.content` → `JSON.parse`.
- `runToolLoop`: `/chat/completions` with `tools: tools.map(t => ({type:"function",
  function:{name,description,parameters: toOpenAiSchema(t.parameters)}}))`,
  `tool_choice:"auto"`. Loop up to `maxToolCalls`: if the assistant message has
  `tool_calls`, execute each via `executeTool`, append the assistant message and one
  `{role:"tool", tool_call_id, content}` per call, repeat; otherwise break. Then a final
  `/chat/completions` with `response_format json_schema (finalSchema)`; parse.

**5. `supabase/functions/_shared/ai/factory.ts` — `createProvider(fn)`**

```ts
export function createProvider(fn: string): LlmProvider;
```

Resolution order for the provider name: `AI_PROVIDER_<FN_UPPER>` (e.g.
`AI_PROVIDER_ASSISTANT`, dashes→underscores) → `AI_PROVIDER` → `"gemini"`.

- `gemini`: requires `GEMINI_API_KEY`; `GEMINI_MODEL` default `gemini-2.5-flash`.
- `openai`: requires `OPENAI_API_KEY`; `OPENAI_MODEL` default `gpt-4o-mini`;
  `OPENAI_BASE_URL` optional.
- `AI_TIMEOUT_MS` default `15000`.
- Unknown provider → `throw new Error("unsupported_provider_" + name)`.
- Missing key → `throw new Error("missing_" + name + "_key")`.

**6. `supabase/functions/_shared/ai/prompts.ts` — Prompt Manager**

Moves every prompt builder, tool definition, response schema, and `PII_PATTERN` out of the
five function `schema.ts` files into one module:

- Assistant: `assistantSystemPrompt(sellerName)`, `assistantTools: LlmTool[]`,
  `assistantFinalSchema: NeutralSchema`, `PII_PATTERN`.
- Work items: `workItemsPrompt(input)`, `workItemsSchema`.
- Draft reply: `draftReplyPrompt(input, sellerName)`, `draftReplySchema`.
- Summarize customer: `summarizeCustomerPrompt(input)`, `summarizeSchema`.
- Parse enquiry: `parseEnquiryPrompt(text, todayIso)`, `parseEnquirySchema`.

Function-specific TS input/output interfaces stay in each function's local `schema.ts`
(they are the function's own contract, imported by its `index.ts`). Only prompts, tool
defs, and response schemas move to the Prompt Manager. Schemas are rewritten in
`NeutralSchema` form (the Gemini adapter reproduces the previous uppercase shape).

### Function refactor (all five)

Each `index.ts` keeps its auth, rate-limit, input validation, telemetry, and (for the
assistant) PII filtering exactly as-is. It swaps the local `createXProvider()` + inline
provider call for:

```ts
import { createProvider } from "../_shared/ai/factory.ts";
import { workItemsPrompt, workItemsSchema } from "../_shared/ai/prompts.ts";
// ...
const provider = createProvider("generate-work-items");
const output = await provider.generateJson<GenerateOutput>({
  messages: [{ role: "user", content: workItemsPrompt(input) }],
  schema: workItemsSchema,
});
```

The assistant passes its four-RPC `executeTool` switch (kept local) into `runToolLoop`.
All five per-function `provider.ts` files are **deleted**.

## Data flow (unchanged externally)

Client → edge function (`index.ts`: auth → rate-limit → validate → build prompt) →
`createProvider(fn)` → `generateJson`/`runToolLoop` → provider `fetch` to Gemini or
OpenAI → parsed structured JSON → (assistant) PII filter → JSON response to client. The
request/response contract to the Flutter app is unchanged.

## Error handling

- Each provider wraps its operation in an `AbortController` timeout; on abort it throws an
  error whose message contains `timeout`/`abort` (functions map that to the existing
  504/timeout responses).
- HTTP failures throw `"<provider>_http_<status>"`; empty/malformed responses throw
  `"<provider>_empty"` / `"<provider>_bad_json"`.
- `createProvider` throws `missing_<provider>_key` / `unsupported_provider_<name>` — the
  function's existing catch maps these to a 500.
- Existing function-level try/catch, telemetry, and error response codes are preserved.

## Testing (Deno, TDD)

Install Deno locally. Unit tests use a mocked `globalThis.fetch` (no network):

- `_shared/ai/schema_test.ts` — `toGeminiSchema` (recursive uppercasing, enum/items/
  required/description preserved) and `toOpenAiSchema` (`additionalProperties:false` on
  objects; nested objects handled).
- `_shared/ai/gemini_test.ts` — `generateJson` builds the expected `generateContent` body
  and parses the candidate text; `runToolLoop` executes tools, feeds `functionResponse`
  back, stops at `maxToolCalls`, and issues the final structured call; timeout aborts.
- `_shared/ai/openai_test.ts` — `generateJson` builds `chat/completions` with
  `response_format json_schema strict` and parses `message.content`; `runToolLoop` handles
  `tool_calls`, appends `role:"tool"` messages, stops at `maxToolCalls`, issues the final
  structured call; timeout aborts.
- `_shared/ai/factory_test.ts` — provider precedence (`AI_PROVIDER_<FN>` > `AI_PROVIDER` >
  default `gemini`); missing key throws; unknown provider throws.

Typecheck: `deno check supabase/functions/**/*.ts`.

Verification commands:
- `deno test supabase/functions/_shared/ai/`
- `deno check supabase/functions/**/*.ts`

A `supabase/functions/deno.json` defines `test`/`check` tasks and lint config.

## Risks / tradeoffs

- **Behavior parity:** the Gemini adapter must reproduce the current request shapes.
  Tests assert the request bodies; default provider stays `gemini` so prod is unaffected.
- **OpenAI strict schema** requires every object property `required` and
  `additionalProperties:false`. Our output schemas already list all properties required;
  the adapter adds `additionalProperties:false`. If a future schema needs optional fields,
  set `strict:false` for that call.
- **Tool-call dialect differences** (Gemini `functionCall`/`functionResponse` vs OpenAI
  `tool_calls`/`role:"tool"`) are normalized inside each `runToolLoop`; the neutral
  `executeTool` contract is identical for both.
- **Deno not in CI:** tests run locally; deployment still uses the Supabase CLI. No CI
  wiring is added in this sub-project.
- **Model defaults:** `OPENAI_MODEL` defaults to `gpt-4o-mini` but is fully overridable
  via env; teams can point it at whatever model they run.
