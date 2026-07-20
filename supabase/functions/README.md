# Closr edge functions — AI provider configuration

All five AI functions (`assistant`, `generate-work-items`, `draft-reply`,
`summarize-customer`, `parse-enquiry`) share one LLM abstraction in
[`_shared/ai/`](./_shared/ai/). Business logic never talks to a provider
directly — it calls `createProvider(fn)` and then `generateJson` /
`runToolLoop`. Adding a provider means implementing `LlmProvider`; no function
code changes.

## Providers

Two adapters ship today: **Gemini** (default) and **OpenAI**. Both implement the
same two capabilities, so any function runs on either.

## Selecting a provider

Resolution order, per function: `AI_PROVIDER_<FN>` → `AI_PROVIDER` → `gemini`.
`<FN>` is the function name uppercased with dashes as underscores.

```
AI_PROVIDER=gemini                     # global default (omit → gemini)
AI_PROVIDER_PARSE_ENQUIRY=openai       # route one function to OpenAI
AI_PROVIDER_GENERATE_WORK_ITEMS=openai
```

## Env vars

| Var | Default | Notes |
| --- | --- | --- |
| `AI_PROVIDER` | `gemini` | Global provider for all functions. |
| `AI_PROVIDER_<FN>` | — | Per-function override (e.g. `AI_PROVIDER_ASSISTANT`). |
| `AI_TIMEOUT_MS` | `15000` | Request timeout (all functions). |
| `GEMINI_API_KEY` | — | Required when the resolved provider is `gemini`. |
| `GEMINI_MODEL` | `gemini-2.5-flash` | |
| `OPENAI_API_KEY` | — | Required when the resolved provider is `openai`. |
| `OPENAI_MODEL` | `gpt-4o-mini` | |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | Override for Azure/proxy/compatible APIs. |

A missing key for the resolved provider throws `missing_<provider>_key`; an
unknown provider name throws `unsupported_provider_<name>`; a non-numeric
`AI_TIMEOUT_MS` throws `invalid_AI_TIMEOUT_MS`.

Set secrets with `supabase secrets set KEY=value` (never commit them).

## Local dev (Deno)

```
cd supabase/functions
deno task test    # unit tests for the AI adapters (mocked fetch)
deno task check   # typecheck the AI functions + shared lib
```

## Notes

- **Gemini is the default**, so production behavior is unchanged unless you opt
  in to OpenAI. Per-function temperatures are preserved (assistant 0.3,
  generate-work-items 0.3, draft-reply 0.4, summarize-customer 0.2,
  parse-enquiry 0).
- OpenAI runs in strict `json_schema` mode. Schemas are authored once as a
  neutral schema and translated per provider — every object becomes
  `additionalProperties:false` with all keys required and optionals expressed as
  `["<type>","null"]` unions.
- `AI_TIMEOUT_MS` applies to every function. `parse-enquiry` is the only
  user-blocking path (the capture flow); if you tune the timeout down for
  interactivity, do it globally aware of the slower functions.
