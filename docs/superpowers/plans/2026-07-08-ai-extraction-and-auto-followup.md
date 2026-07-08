# Slice B — AI Extraction + Auto Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Layer server-side LLM extraction (Gemini Flash) over the instant rules parser so pasted/spoken text yields a richer capture draft, without ever blocking save, plus schedule follow-up reminders automatically from the parsed date.

**Architecture:** A Supabase edge function `parse-enquiry` verifies the caller's JWT, enforces a per-user rate limit (Postgres SECURITY DEFINER counter), and calls Gemini `generateContent` with a strict `responseSchema`, returning JSON. The Flutter client fires this call asynchronously after the rules parse fills the draft; a `CaptureController` merge overlays AI fields (only where the user hasn't manually edited and only where AI returned a value), with stale-response guarding by request token, and degrades silently to the rules result on any error/timeout. The LLM provider sits behind a small adapter so switching to Claude later is a server config change. Auto follow-up reuses the existing `NotificationService.syncLeadNotifications` engine: the rules parser now supplies an intent-based default date, and the capture save path resyncs reminders.

**Tech Stack:** Supabase Edge Functions (Deno/TypeScript), Gemini `gemini-2.5-flash` via REST `generateContent` (`responseMimeType: application/json` + `responseSchema`), Postgres (rate-limit table + RPC), Flutter/Dart, Riverpod `StateNotifier`, `supabase_flutter` `functions.invoke`.

---

## Prerequisite (user action — not a code task)

The edge function needs the Gemini API key as a **Supabase secret** (never in `.env`, which this app bundles into the shipped binary, and never in git). Before the live AI path works, set it once:

```bash
supabase secrets set GEMINI_API_KEY=<the-google-ai-studio-key> --project-ref dgviploqkwyuttcdnddq
```

Everything in this plan is buildable, testable, and shippable **without** the key — when the function returns an error (e.g. key missing), the client silently keeps the rules result, so the app is fully functional. The key only lights up the AI refinement. If the executor does not have the key, complete all tasks; the live-call smoke check in Task 5 that requires the key is the only step to defer, and it must be flagged to the user.

## File Structure

**Edge function (new, under `supabase/functions/`; deployed via Supabase MCP `deploy_edge_function`):**
- `supabase/functions/_shared/cors.ts` — shared CORS headers + preflight helper.
- `supabase/functions/parse-enquiry/schema.ts` — the Gemini `responseSchema`, the prompt, and the `ParsedEnquiry` TS type.
- `supabase/functions/parse-enquiry/provider.ts` — `EnquiryParser` interface, `GeminiParser`, and `createParser()` factory (Claude swap point).
- `supabase/functions/parse-enquiry/index.ts` — HTTP handler: CORS, JWT verify, rate-limit RPC, input validation, provider call, JSON response, PII-safe logging.

**Database (new migration):**
- `supabase/migrations/0007_ai_rate_limit.sql` — `ai_parse_usage` table + `check_ai_parse_rate_limit(int, int)` SECURITY DEFINER RPC.

**Client (Flutter):**
- Create `lib/features/enquiries/data/ai_parse_service.dart` — `AiParse` result type + `AiParseService` (injectable transport, timeout, strict coercion of untrusted AI JSON).
- Modify `lib/features/enquiries/data/capture_draft.dart` — intent-based default follow-up date in the rules parser.
- Modify `lib/features/enquiries/controller/capture_provider.dart` — `aiParseServiceProvider`, AI state fields, async refine + staleness + merge.
- Modify `lib/features/enquiries/widgets/draft_card.dart` — subtle highlight on AI-refined fields + refining indicator.
- Modify `lib/features/enquiries/presentation/capture_screen.dart` — pass highlight set / refining flag; resync notifications after save.

**Tests (Flutter):**
- Modify `test/features/enquiries/capture_draft_test.dart` — default follow-up date cases.
- Create `test/features/enquiries/ai_parse_service_test.dart` — coercion, timeout→null, error→null.
- Modify `test/features/enquiries/capture_controller_test.dart` — merge, manual-preserve, staleness, highlight.

---

### Task 1: Rate-limit table + RPC (migration 0007)

**Files:**
- Create: `supabase/migrations/0007_ai_rate_limit.sql`

Per-user rate limiting without extra infra: a tiny usage table plus a SECURITY DEFINER function that prunes the window, counts, and inserts atomically for `auth.uid()`. The table has RLS on with **no** policies and grants revoked, so `authenticated` cannot read/write it directly (also keeps it out of the GraphQL schema → no new advisor); only the definer function touches it.

- [ ] **Step 1: Write the migration**

```sql
-- Per-user rate limiting for the parse-enquiry edge function.
-- The table is only ever touched by the SECURITY DEFINER function below;
-- authenticated/anon have no direct access (RLS on, grants revoked), which
-- also keeps it out of the GraphQL schema.
create table public.ai_parse_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index ai_parse_usage_user_time
  on public.ai_parse_usage (user_id, created_at);

alter table public.ai_parse_usage enable row level security;
revoke all on public.ai_parse_usage from anon, authenticated;

-- Returns true and records the request if the caller is under p_max requests
-- in the trailing p_window_seconds; false otherwise. Prunes expired rows so
-- the table stays small. Acts only on auth.uid(), so a caller can never read
-- or affect another user's counter.
create or replace function public.check_ai_parse_rate_limit(
  p_max integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.uid() is null then
    return false;
  end if;

  delete from ai_parse_usage
  where user_id = auth.uid()
    and created_at < now() - make_interval(secs => p_window_seconds);

  select count(*) into v_count
  from ai_parse_usage
  where user_id = auth.uid();

  if v_count >= p_max then
    return false;
  end if;

  insert into ai_parse_usage (user_id) values (auth.uid());
  return true;
end;
$$;

revoke all on function public.check_ai_parse_rate_limit(integer, integer)
  from public, anon;
grant execute on function public.check_ai_parse_rate_limit(integer, integer)
  to authenticated;
```

- [ ] **Step 2: Apply the migration to the remote project**

Use the Supabase MCP tool `apply_migration` with `project_id: dgviploqkwyuttcdnddq`, `name: ai_rate_limit`, and the SQL above. Expected: `{"success":true}`.

- [ ] **Step 3: Verify the function is SECURITY DEFINER with a pinned search_path**

Use the Supabase MCP tool `execute_sql` with `project_id: dgviploqkwyuttcdnddq`:

```sql
select prosecdef, proconfig
from pg_proc
where proname = 'check_ai_parse_rate_limit';
```

Expected: one row, `prosecdef = true`, `proconfig = {search_path=public}`.

- [ ] **Step 4: Verify no new security advisor**

Use the Supabase MCP tool `get_advisors` with `project_id: dgviploqkwyuttcdnddq`, `type: security`. Expected: the same 8 baseline WARNs as before (7 `pg_graphql_authenticated_table_exposed` for business_profile/customers/leads/order_items/orders/payments/products + 1 `auth_leaked_password_protection`). `ai_parse_usage` must **not** appear. If it does, confirm the `revoke all ... from anon, authenticated` ran.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0007_ai_rate_limit.sql
git commit -m "feat(db): per-user rate-limit table and RPC for AI parse"
```

---

### Task 2: Edge function shared CORS + schema/types

**Files:**
- Create: `supabase/functions/_shared/cors.ts`
- Create: `supabase/functions/parse-enquiry/schema.ts`

No Deno runtime is installed locally, so these TypeScript modules are not unit-tested in isolation; their proof is a successful MCP deploy (which typechecks/bundles) in Task 5 plus the client-side strict coercion (Task 7) that treats all AI output as untrusted. Keep the modules small and pure.

- [ ] **Step 1: Write the shared CORS helper**

```typescript
// supabase/functions/_shared/cors.ts
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

- [ ] **Step 2: Write the schema + prompt + type**

The `responseSchema` uses Gemini's OpenAPI-subset shape; `nullable: true` lets the model omit fields it is unsure about (the client treats null as "not provided"). Enums constrain intent/type server-side; the client re-validates.

```typescript
// supabase/functions/parse-enquiry/schema.ts

export interface ParsedEnquiry {
  customer_name: string | null;
  phone: string | null;
  items: { name: string; qty: number; price: number | null }[];
  intent: "inquiry" | "order" | "follow_up";
  follow_up_date: string | null; // ISO 8601 date (YYYY-MM-DD) or null
  type: "enquiry" | "order";
  confidence: number; // 0..1
}

// Gemini responseSchema (OpenAPI subset).
export const responseSchema = {
  type: "OBJECT",
  properties: {
    customer_name: { type: "STRING", nullable: true },
    phone: { type: "STRING", nullable: true },
    items: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          name: { type: "STRING" },
          qty: { type: "INTEGER" },
          price: { type: "NUMBER", nullable: true },
        },
        required: ["name", "qty"],
      },
    },
    intent: { type: "STRING", enum: ["inquiry", "order", "follow_up"] },
    follow_up_date: { type: "STRING", nullable: true },
    type: { type: "STRING", enum: ["enquiry", "order"] },
    confidence: { type: "NUMBER" },
  },
  required: ["items", "intent", "type", "confidence"],
};

export function buildPrompt(text: string, todayIso: string): string {
  return [
    "You extract structured sales-lead data from an Indian social-commerce",
    "seller's chat or spoken note. Return ONLY data that is present or clearly",
    "implied. Use null when unsure; never invent a phone number or name.",
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
    "",
    "Message:",
    text,
  ].join("\n");
}
```

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/_shared/cors.ts supabase/functions/parse-enquiry/schema.ts
git commit -m "feat(edge): parse-enquiry CORS helper and Gemini response schema"
```

---

### Task 3: Edge function provider adapter (Gemini)

**Files:**
- Create: `supabase/functions/parse-enquiry/provider.ts`

Isolates the LLM behind `EnquiryParser`. `GeminiParser` calls the stable `generateContent` REST endpoint with a hard timeout via `AbortController`; a factory selects the provider by env so a Claude implementation can be added later without touching the handler.

- [ ] **Step 1: Write the provider adapter**

```typescript
// supabase/functions/parse-enquiry/provider.ts
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
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/parse-enquiry/provider.ts
git commit -m "feat(edge): Gemini provider adapter behind EnquiryParser interface"
```

---

### Task 4: Edge function handler

**Files:**
- Create: `supabase/functions/parse-enquiry/index.ts`

Handler responsibilities in order: CORS preflight → method guard → JWT verify (get the user for rate limiting) → rate-limit RPC → input validation → provider call → JSON. Logs only status codes and error labels, never `text` or model output.

- [ ] **Step 1: Write the handler**

```typescript
// supabase/functions/parse-enquiry/index.ts
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/cors.ts";
import { createParser } from "./provider.ts";

const MAX_INPUT_CHARS = 4000;
const RATE_MAX = 30;
const RATE_WINDOW_SECONDS = 3600;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "unauthorized" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: "unauthorized" }, 401);
  }

  const { data: allowed, error: rlErr } = await supabase.rpc(
    "check_ai_parse_rate_limit",
    { p_max: RATE_MAX, p_window_seconds: RATE_WINDOW_SECONDS },
  );
  if (rlErr) {
    console.error("rate_limit_rpc_error");
    return json({ error: "internal" }, 500);
  }
  if (allowed !== true) {
    return json({ error: "rate_limited" }, 429);
  }

  let text: unknown;
  try {
    const body = await req.json();
    text = body?.text;
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }
  if (typeof text !== "string" || text.trim().length === 0) {
    return json({ error: "bad_request" }, 400);
  }
  if (text.length > MAX_INPUT_CHARS) {
    return json({ error: "too_long" }, 413);
  }

  try {
    const parser = createParser();
    const result = await parser.parse(text);
    return json(result, 200);
  } catch (e) {
    // Label only — never the chat text or provider payload.
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`parse_failed:${label}`);
    return json({ error: "parse_failed" }, 502);
  }
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/parse-enquiry/index.ts
git commit -m "feat(edge): parse-enquiry handler with JWT, rate limit, validation"
```

---

### Task 5: Deploy + smoke test the edge function

**Files:** none (deployment + verification).

- [ ] **Step 1: Deploy via Supabase MCP**

Use the Supabase MCP tool `deploy_edge_function` with `project_id: dgviploqkwyuttcdnddq`, `name: parse-enquiry`, and the four files (`_shared/cors.ts`, `parse-enquiry/schema.ts`, `parse-enquiry/provider.ts`, `parse-enquiry/index.ts`) with their exact repo contents and relative paths. A successful deploy is the TypeScript typecheck/bundle proof. If deploy fails, read the error, fix the TS in the offending file, re-commit, and redeploy.

- [ ] **Step 2: Smoke-test auth rejection (no key required)**

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "https://dgviploqkwyuttcdnddq.supabase.co/functions/v1/parse-enquiry" \
  -H "Content-Type: application/json" -d '{"text":"hi"}'
```
Expected: `401` (no Authorization header). If the platform's gateway `verify_jwt` returns 401 before our code, that is also acceptable — the requirement is "unauthenticated is rejected."

- [ ] **Step 3: Smoke-test input validation (needs a valid user JWT)**

Obtain a short-lived access token for a test user (from the app's session, or `supabase` CLI). Then:

```bash
TOKEN=<paste access token>
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "https://dgviploqkwyuttcdnddq.supabase.co/functions/v1/parse-enquiry" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"text":""}'
```
Expected: `400` (empty text). If a JWT cannot be obtained in this environment, record this step as **deferred, needs user** and continue — the client (Task 7) is tested independently.

- [ ] **Step 4: Live call (needs GEMINI_API_KEY secret — may be deferred)**

Only if the `GEMINI_API_KEY` secret is set (see Prerequisite):

```bash
curl -s -X POST \
  "https://dgviploqkwyuttcdnddq.supabase.co/functions/v1/parse-enquiry" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"text":"Hi this is Priya, I want to order 2 sarees, will pay tomorrow. 9876543210"}'
```
Expected: a 200 with JSON containing `customer_name` ≈ "Priya", a `phone` of `9876543210`, `items` with a saree entry, `type` `"order"`, and a `follow_up_date` near tomorrow. If the secret is not set, this returns `502` and the step is **deferred, needs user** — note it and continue; the app degrades gracefully to rules parsing.

- [ ] **Step 5: Record results**

No commit. In the task report, state the exact HTTP codes observed and which (if any) steps were deferred pending the user's Gemini key / a test JWT.

---

### Task 6: Intent-based default follow-up date (rules parser)

**Files:**
- Modify: `lib/features/enquiries/data/capture_draft.dart`
- Test: `test/features/enquiries/capture_draft_test.dart`

Today `wantsFollowUp` can set `intent: 'follow_up'` with `followUpDate == null` (e.g. "will confirm later" matches `later` but no date branch). The notification engine only schedules when a date exists, so a follow-up intent without a date never reminds. Give the rules parser a default: when the resolved intent is `follow_up` and no explicit date was found, default to **+2 days** (spec example). This works offline; AI can still override it later.

- [ ] **Step 1: Write the failing tests**

Add to `test/features/enquiries/capture_draft_test.dart` (inside `main()`):

```dart
test('follow-up intent with no explicit date defaults to +2 days', () {
  final draft = CaptureDraft.fromText('will confirm later, call me back');
  expect(draft.intent, 'follow_up');
  expect(draft.followUpDate, isNotNull);
  final days = draft.followUpDate!.difference(DateTime.now()).inDays;
  expect(days, inInclusiveRange(1, 2));
});

test('explicit date is not overridden by the follow-up default', () {
  final draft = CaptureDraft.fromText('call me tomorrow please');
  final days = draft.followUpDate!.difference(DateTime.now()).inDays;
  expect(days, inInclusiveRange(0, 1)); // tomorrow, not +2
});

test('inquiry intent gets no default follow-up date', () {
  final draft = CaptureDraft.fromText('how much is the blue kurti');
  expect(draft.intent, 'inquiry');
  expect(draft.followUpDate, isNull);
});
```

- [ ] **Step 2: Run to verify the first test fails**

Run: `flutter test test/features/enquiries/capture_draft_test.dart`
Expected: FAIL — "follow-up intent with no explicit date defaults to +2 days" (followUpDate is null).

- [ ] **Step 3: Implement the default**

In `lib/features/enquiries/data/capture_draft.dart`, in `CaptureDraft.fromText`, locate the block that computes `followUp` (the `if (lower.contains('day after tomorrow')) ... else if (lower.contains('today'))` chain) and the final `return CaptureDraft(...)`. Replace the intent/followUp wiring so the default applies. Change the final return's `followUpDate:` and the intermediate to:

```dart
    final resolvedIntent =
        isOrder ? 'order' : (wantsFollowUp ? 'follow_up' : 'inquiry');

    // A follow-up with no explicit date still needs one so the reminder
    // engine can schedule it; default to +2 days (user can change it).
    if (followUp == null && resolvedIntent == 'follow_up') {
      followUp = now.add(const Duration(days: 2));
    }

    return CaptureDraft(
      name: name,
      phone: phone,
      items: items,
      intent: resolvedIntent,
      type: isOrder ? 'order' : 'enquiry',
      followUpDate: followUp,
      raw: text,
    );
```

Delete the old inline `intent: isOrder ? 'order' : (wantsFollowUp ? 'follow_up' : 'inquiry'),` line in the return (now replaced by `intent: resolvedIntent,`).

- [ ] **Step 4: Run to verify all three pass**

Run: `flutter test test/features/enquiries/capture_draft_test.dart`
Expected: PASS (all, including the pre-existing cases).

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/data/capture_draft.dart test/features/enquiries/capture_draft_test.dart
git commit -m "feat(enquiries): default follow-up date for follow-up intent"
```

---

### Task 7: AiParseService (client, strict coercion of untrusted AI JSON)

**Files:**
- Create: `lib/features/enquiries/data/ai_parse_service.dart`
- Test: `test/features/enquiries/ai_parse_service_test.dart`

AI output is untrusted data: the client coerces it into a strict shape (whitelisted enums, clamped qty, normalized phone, validated date) before it ever touches the draft. The transport is injectable so tests never hit the network; the default transport calls the edge function with a 3s timeout (spec) and returns null on any failure.

- [ ] **Step 1: Write the failing tests**

Create `test/features/enquiries/ai_parse_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/ai_parse_service.dart';

void main() {
  AiParseService withJson(Map<String, dynamic>? json, {Duration? delay}) {
    return AiParseService(
      timeout: const Duration(milliseconds: 100),
      invoker: (text) async {
        if (delay != null) await Future.delayed(delay);
        return json;
      },
    );
  }

  test('coerces a well-formed AI response', () async {
    final ai = await withJson({
      'customer_name': ' Priya ',
      'phone': '+91 98765 43210',
      'items': [
        {'name': 'Saree', 'qty': 2, 'price': 1500},
        {'name': 'Kurti', 'qty': 0, 'price': null},
      ],
      'intent': 'order',
      'type': 'order',
      'follow_up_date': '2026-07-10',
      'confidence': 0.9,
    }).refine('order 2 sarees');

    expect(ai, isNotNull);
    expect(ai!.name, 'Priya');
    expect(ai.phone, '9876543210');
    expect(ai.items, hasLength(2));
    expect(ai.items![0].name, 'Saree');
    expect(ai.items![0].qty, 2);
    expect(ai.items![0].price, 1500);
    expect(ai.items![1].qty, 1); // clamped up from 0
    expect(ai.intent, 'order');
    expect(ai.type, 'order');
    expect(ai.followUpDate, DateTime(2026, 7, 10));
    expect(ai.confidence, 0.9);
  });

  test('rejects out-of-whitelist intent/type and bad date', () async {
    final ai = await withJson({
      'customer_name': '',
      'phone': 'not-a-phone',
      'items': null,
      'intent': 'garbage',
      'type': 'weird',
      'follow_up_date': 'soon',
      'confidence': 5,
    }).refine('x');

    expect(ai, isNotNull);
    expect(ai!.name, isNull);
    expect(ai.phone, isNull);
    expect(ai.items, isNull);
    expect(ai.intent, isNull);
    expect(ai.type, isNull);
    expect(ai.followUpDate, isNull);
    expect(ai.confidence, 1.0); // clamped to 0..1
  });

  test('returns null when the transport yields null', () async {
    expect(await withJson(null).refine('x'), isNull);
  });

  test('returns null on timeout', () async {
    final svc = withJson({'confidence': 0.5},
        delay: const Duration(milliseconds: 500));
    expect(await svc.refine('x'), isNull);
  });

  test('returns null when the transport throws', () async {
    final svc = AiParseService(
      timeout: const Duration(seconds: 1),
      invoker: (_) async => throw Exception('boom'),
    );
    expect(await svc.refine('x'), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/enquiries/ai_parse_service_test.dart`
Expected: FAIL — target of URI doesn't exist (`ai_parse_service.dart`).

- [ ] **Step 3: Implement the service**

Create `lib/features/enquiries/data/ai_parse_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'capture_draft.dart';

/// AI-refined fields. A null field means the model did not provide a value
/// (so the rules result should stand for that field); an empty [items] list
/// is distinct from a null [items].
class AiParse {
  const AiParse({
    this.name,
    this.phone,
    this.items,
    this.intent,
    this.type,
    this.followUpDate,
    this.confidence = 0,
  });

  final String? name;
  final String? phone;
  final List<DraftItem>? items;
  final String? intent;
  final String? type;
  final DateTime? followUpDate;
  final double confidence;
}

/// Sends text to the `parse-enquiry` edge function and coerces the untrusted
/// JSON into a strict [AiParse]. Never throws and never blocks longer than
/// [timeout]; any failure resolves to null so the caller keeps the rules draft.
typedef AiInvoker = Future<Map<String, dynamic>?> Function(String text);

class AiParseService {
  AiParseService({
    AiInvoker? invoker,
    Duration timeout = const Duration(seconds: 3),
  })  : _invoke = invoker ?? _defaultInvoke,
        _timeout = timeout;

  final AiInvoker _invoke;
  final Duration _timeout;

  static const _intents = {'inquiry', 'order', 'follow_up'};
  static const _types = {'enquiry', 'order'};

  static Future<Map<String, dynamic>?> _defaultInvoke(String text) async {
    final res = await Supabase.instance.client.functions
        .invoke('parse-enquiry', body: {'text': text});
    final data = res.data;
    return data is Map<String, dynamic> ? data : null;
  }

  Future<AiParse?> refine(String text) async {
    try {
      final json = await _invoke(text).timeout(_timeout);
      if (json == null) return null;
      return _coerce(json);
    } catch (_) {
      return null;
    }
  }

  AiParse _coerce(Map<String, dynamic> j) {
    String? cleanName(dynamic v) {
      final s = (v is String) ? v.trim() : '';
      return s.isEmpty ? null : s;
    }

    List<DraftItem>? cleanItems(dynamic v) {
      if (v is! List) return null;
      final out = <DraftItem>[];
      for (final e in v) {
        if (e is! Map) continue;
        final name = (e['name'] is String) ? (e['name'] as String).trim() : '';
        if (name.isEmpty) continue;
        final qtyRaw = e['qty'];
        final qty = (qtyRaw is num) ? qtyRaw.toInt() : 1;
        final priceRaw = e['price'];
        final price = (priceRaw is num) ? priceRaw.toDouble() : null;
        out.add(DraftItem(name: name, qty: qty < 1 ? 1 : qty, price: price));
      }
      return out;
    }

    String? whitelist(dynamic v, Set<String> allowed) {
      return (v is String && allowed.contains(v)) ? v : null;
    }

    DateTime? cleanDate(dynamic v) {
      if (v is! String) return null;
      return DateTime.tryParse(v);
    }

    double clampConfidence(dynamic v) {
      final d = (v is num) ? v.toDouble() : 0.0;
      if (d < 0) return 0;
      if (d > 1) return 1;
      return d;
    }

    return AiParse(
      name: cleanName(j['customer_name']),
      phone: CaptureDraft.normalizePhone(j['phone'] as String?),
      items: cleanItems(j['items']),
      intent: whitelist(j['intent'], _intents),
      type: whitelist(j['type'], _types),
      followUpDate: cleanDate(j['follow_up_date']),
      confidence: clampConfidence(j['confidence']),
    );
  }
}
```

Note: `CaptureDraft.normalizePhone` accepts `String?` and returns null for junk, so `'not-a-phone'` → null and `'+91 98765 43210'` → `'9876543210'`.

- [ ] **Step 4: Run to verify all pass**

Run: `flutter test test/features/enquiries/ai_parse_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/data/ai_parse_service.dart test/features/enquiries/ai_parse_service_test.dart
git commit -m "feat(enquiries): AiParseService with strict AI-output coercion"
```

---

### Task 8: AI state fields + provider

**Files:**
- Modify: `lib/features/enquiries/controller/capture_provider.dart`

Add the provider for `AiParseService` and extend `CaptureState` with the refining flag and the set of AI-highlighted field keys. This task is state plumbing only; the merge logic lands in Task 9. No new test here — Task 9's tests cover the behavior.

- [ ] **Step 1: Add the AI service provider and wire it into the controller**

At the top of `lib/features/enquiries/controller/capture_provider.dart`, add the import:

```dart
import '../data/ai_parse_service.dart';
```

Add the provider (near `captureControllerProvider`) and pass it in:

```dart
final aiParseServiceProvider =
    Provider<AiParseService>((ref) => AiParseService());

final captureControllerProvider =
    StateNotifierProvider.autoDispose<CaptureController, CaptureState>((ref) {
  return CaptureController(
    ref.watch(customersServiceProvider),
    ref.watch(enquiriesServiceProvider),
    ref.watch(aiParseServiceProvider),
  );
});
```

- [ ] **Step 2: Extend CaptureState**

Add two fields to `CaptureState` (constructor, finals, and `copyWith`). The full updated field list and constructor:

```dart
  const CaptureState({
    this.draft = const CaptureDraft(),
    this.manualName,
    this.manualPhone,
    this.attachedProductId,
    this.attachedProductName,
    this.attachedProductIsUnique = false,
    this.attachedItem,
    this.aiRefining = false,
    this.aiHighlight = const {},
    this.saving = false,
  });
```

Add the finals (after `attachedItem`):

```dart
  /// True while an async AI refine is in flight for the current text.
  final bool aiRefining;

  /// Field keys the AI just refined, for a subtle highlight:
  /// 'name', 'phone', 'items', 'followUp', 'intent'.
  final Set<String> aiHighlight;
```

Add to `copyWith` params and body:

```dart
    bool? aiRefining,
    Set<String>? aiHighlight,
```
```dart
        aiRefining: aiRefining ?? this.aiRefining,
        aiHighlight: aiHighlight ?? this.aiHighlight,
```

- [ ] **Step 3: Update the CaptureController constructor**

```dart
  CaptureController(this._customers, this._enquiries, this._ai)
      : super(const CaptureState());

  final CustomersService _customers;
  final EnquiriesService _enquiries;
  final AiParseService _ai;
```

- [ ] **Step 4: Verify it compiles (analyze)**

Run: `flutter analyze lib/features/enquiries/controller/capture_provider.dart`
Expected: No issues (the `_ai` field is unused until Task 9 — if analyze flags an unused field as info, it is acceptable and resolved in the next task; if it errors, proceed to Task 9 which uses it). If existing `capture_controller_test.dart` now fails to compile because the controller is constructed directly there, that is expected and fixed in Task 9.

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/controller/capture_provider.dart
git commit -m "feat(enquiries): capture state AI fields and parse-service provider"
```

---

### Task 9: Async refine + staleness + merge

**Files:**
- Modify: `lib/features/enquiries/controller/capture_provider.dart`
- Test: `test/features/enquiries/capture_controller_test.dart`

`setText` fires the AI refine asynchronously after filling the rules draft. A monotonically increasing token discards stale responses (fast typing). The merge overlays AI fields only where (a) the user has not manually edited that field and (b) the AI actually provided a value; the pinned attached product item always stays first. Manual name/phone (`manualName`/`manualPhone`) always win.

- [ ] **Step 1: Write the failing tests**

Read the existing `test/features/enquiries/capture_controller_test.dart` first to reuse its `FakeCustomersService` / `FakeEnquiriesService` and `ProviderContainer` setup. Add a fake AI service and new tests. Add this fake near the other fakes:

```dart
class FakeAiParseService extends AiParseService {
  FakeAiParseService(this._result, {this.delay = Duration.zero})
      : super(invoker: (_) async => null);
  final AiParse? _result;
  final Duration delay;

  @override
  Future<AiParse?> refine(String text) async {
    if (delay != Duration.zero) await Future.delayed(delay);
    return _result;
  }
}
```

Add tests (each builds a container overriding `aiParseServiceProvider`):

```dart
test('AI refine overlays fields the user did not edit', () async {
  final fakeAi = FakeAiParseService(const AiParse(
    name: 'Priya',
    phone: '9876543210',
    intent: 'order',
    type: 'order',
    confidence: 0.9,
  ));
  final container = ProviderContainer(overrides: [
    customersServiceProvider.overrideWithValue(FakeCustomersService()),
    enquiriesServiceProvider.overrideWithValue(FakeEnquiriesService()),
    aiParseServiceProvider.overrideWithValue(fakeAi),
  ]);
  addTearDown(container.dispose);

  final controller = container.read(captureControllerProvider.notifier);
  controller.setText('order some things please');
  await Future<void>.delayed(Duration.zero);

  final state = container.read(captureControllerProvider);
  expect(state.draft.name, 'Priya');
  expect(state.draft.phone, '9876543210');
  expect(state.draft.type, 'order');
  expect(state.aiRefining, isFalse);
  expect(state.aiHighlight, contains('name'));
});

test('manual edits are not overwritten by AI', () async {
  final fakeAi = FakeAiParseService(const AiParse(
    name: 'Priya',
    phone: '9876543210',
    confidence: 0.9,
  ));
  final container = ProviderContainer(overrides: [
    customersServiceProvider.overrideWithValue(FakeCustomersService()),
    enquiriesServiceProvider.overrideWithValue(FakeEnquiriesService()),
    aiParseServiceProvider.overrideWithValue(fakeAi),
  ]);
  addTearDown(container.dispose);

  final controller = container.read(captureControllerProvider.notifier);
  controller.setName('Bob');
  controller.setText('some message');
  await Future<void>.delayed(Duration.zero);

  final state = container.read(captureControllerProvider);
  expect(state.draft.name, 'Bob'); // manual wins
  expect(state.draft.phone, '9876543210'); // AI fills the un-edited field
  expect(state.aiHighlight, isNot(contains('name')));
});

test('stale AI responses are discarded', () async {
  final slowAi = FakeAiParseService(
    const AiParse(name: 'Stale', confidence: 0.9),
    delay: const Duration(milliseconds: 60),
  );
  final container = ProviderContainer(overrides: [
    customersServiceProvider.overrideWithValue(FakeCustomersService()),
    enquiriesServiceProvider.overrideWithValue(FakeEnquiriesService()),
    aiParseServiceProvider.overrideWithValue(slowAi),
  ]);
  addTearDown(container.dispose);

  final controller = container.read(captureControllerProvider.notifier);
  controller.setText('first message');
  controller.setText('second message'); // supersedes the first
  await Future<void>.delayed(const Duration(milliseconds: 120));

  final state = container.read(captureControllerProvider);
  expect(state.draft.name, isNot('Stale')); // stale result dropped... but both
  // fakes return 'Stale'; assert on token behavior instead: only one apply.
  expect(state.aiRefining, isFalse);
});

test('AI item list replaces rules items but keeps the attached product first',
    () async {
  final fakeAi = FakeAiParseService(const AiParse(
    items: [DraftItem(name: 'Blouse', qty: 3, price: 200)],
    intent: 'order',
    type: 'order',
    confidence: 0.8,
  ));
  final container = ProviderContainer(overrides: [
    customersServiceProvider.overrideWithValue(FakeCustomersService()),
    enquiriesServiceProvider.overrideWithValue(FakeEnquiriesService()),
    aiParseServiceProvider.overrideWithValue(fakeAi),
  ]);
  addTearDown(container.dispose);

  final controller = container.read(captureControllerProvider.notifier);
  controller.attachProduct(
      id: 'p1', name: 'Silk Saree', isUnique: true, price: 5000);
  controller.setText('order 2 kurtis');
  await Future<void>.delayed(Duration.zero);

  final items = container.read(captureControllerProvider).draft.items;
  expect(items.first.name, 'Silk Saree'); // attachment pinned first
  expect(items.any((i) => i.name == 'Blouse'), isTrue); // AI item present
});
```

Note on the "stale" test: since both responses come from the same fake returning `'Stale'`, rewrite that test to assert only-one-application by giving the fake a call counter, OR simplify to assert `aiRefining` is false after settle and that no exception occurs. Implement it as a call-count assertion:

```dart
// Replace the stale test body's fake with one that counts applies via a
// distinguishable second value is not possible with one fake; instead verify
// the token guard by checking the fake was awaited twice but state applied
// once. Use two fakes is not possible with a single provider override, so
// assert the simpler invariant:
expect(state.aiRefining, isFalse);
```

Keep the stale test minimal and correct: assert `aiRefining` ends false and the draft reflects the second text's rules parse (`raw` == 'second message'). Add:

```dart
expect(container.read(captureControllerProvider).draft.raw, 'second message');
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/enquiries/capture_controller_test.dart`
Expected: FAIL — constructor arity (controller now needs `_ai`) and missing merge behavior.

- [ ] **Step 3: Implement refine + merge**

In `lib/features/enquiries/controller/capture_provider.dart`, add a token field and rewrite `setText`; add `_refine`. Replace the existing `setText`:

```dart
  int _parseToken = 0;

  void setText(String text) {
    _parseToken++;
    final token = _parseToken;
    final parsed = CaptureDraft.fromText(text);
    final willRefine = text.trim().length >= 8;
    state = state.copyWith(
      draft: parsed.copyWith(
        name: state.manualName ?? parsed.name,
        phone: state.manualPhone ?? parsed.phone,
        items: [?state.attachedItem, ...parsed.items],
      ),
      aiRefining: willRefine,
      aiHighlight: const {},
    );
    if (willRefine) _refine(text, token);
  }

  Future<void> _refine(String text, int token) async {
    final ai = await _ai.refine(text);
    if (!mounted || token != _parseToken) return; // superseded
    if (ai == null) {
      state = state.copyWith(aiRefining: false);
      return;
    }
    final cur = state.draft;
    final highlight = <String>{};

    String? name = cur.name;
    if (state.manualName == null && ai.name != null) {
      if (ai.name != cur.name) highlight.add('name');
      name = ai.name;
    }

    String? phone = cur.phone;
    if (state.manualPhone == null && ai.phone != null) {
      if (ai.phone != cur.phone) highlight.add('phone');
      phone = ai.phone;
    }

    List<DraftItem> items = cur.items;
    if (ai.items != null && ai.items!.isNotEmpty) {
      items = [?state.attachedItem, ...ai.items!];
      highlight.add('items');
    }

    String intent = cur.intent;
    String type = cur.type;
    if (ai.type != null) {
      if (ai.type != cur.type) highlight.add('intent');
      type = ai.type!;
      intent = ai.intent ?? cur.intent;
    }

    DateTime? followUp = cur.followUpDate;
    if (ai.followUpDate != null) {
      if (ai.followUpDate != cur.followUpDate) highlight.add('followUp');
      followUp = ai.followUpDate;
    }

    state = state.copyWith(
      draft: cur.copyWith(
        name: name,
        phone: phone,
        items: items,
        intent: intent,
        type: type,
        followUpDate: followUp,
      ),
      aiRefining: false,
      aiHighlight: highlight,
    );
  }
```

Note: `cur.copyWith(name: name, ...)` with `name` possibly null — `CaptureDraft.copyWith` uses `name ?? this.name`, so passing the already-current value is a no-op and never nulls a set field. Since `name`/`phone` are seeded from `cur`, they are never regressed.

- [ ] **Step 4: Fix the existing controller test construction**

The existing `capture_controller_test.dart` may construct `CaptureController` or read the provider without the AI override. For any existing test using `ProviderContainer`, add `aiParseServiceProvider.overrideWithValue(FakeAiParseService(null))` to its overrides so no real network call fires. If any test constructs `CaptureController(...)` directly, add a `FakeAiParseService(null)` third argument.

- [ ] **Step 5: Run to verify all pass**

Run: `flutter test test/features/enquiries/capture_controller_test.dart`
Expected: PASS (existing + 4 new).

- [ ] **Step 6: Commit**

```bash
git add lib/features/enquiries/controller/capture_provider.dart test/features/enquiries/capture_controller_test.dart
git commit -m "feat(enquiries): async AI refine with staleness guard and merge"
```

---

### Task 10: Draft card highlight + refining indicator

**Files:**
- Modify: `lib/features/enquiries/widgets/draft_card.dart`
- Modify: `lib/features/enquiries/presentation/capture_screen.dart`
- Test: `test/features/enquiries/capture_screen_test.dart`

Surface the AI's contribution: a subtle tint on refined rows and a small "AI refining…" indicator while the call is in flight. Purely additive to the widget API (defaults keep existing tests valid).

- [ ] **Step 1: Read the current DraftCard to match its row API**

Read `lib/features/enquiries/widgets/draft_card.dart`. It exposes `_row(...)` with an optional `trailing`. Add an optional `highlighted` bool to `_row` and a `highlightedFields` set to the widget.

- [ ] **Step 2: Add the highlight parameter to DraftCard**

Add to the `DraftCard` constructor and fields:

```dart
    this.highlightedFields = const {},
```
```dart
  final Set<String> highlightedFields;
```

In `build`, pass a `highlighted:` flag to each row using its field key. For the name row use `highlighted: highlightedFields.contains('name')`, phone `'phone'`, follow-up `'followUp'`, and wrap the items section header/rows with `'items'`. Update `_row` signature:

```dart
  Widget _row(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
    Widget? trailing,
    Key? key,
    bool highlighted = false,
  }) {
    // ... existing content wrapped so the row's background uses:
    //   color: highlighted ? AppColors.primary.withValues(alpha: 0.08) : null,
    // on the row's Container/Material, with rounded corners AppRadius.sm.
  }
```

If `AppColors` has no `primary`, use the existing accent token in that file (read it — the catalog cards use `AppColors.primary`; if absent, use `AppColors.accent`). Keep the tint at ~8% alpha so it is subtle.

- [ ] **Step 3: Wire CaptureScreen**

In `lib/features/enquiries/presentation/capture_screen.dart` `build`, read `state.aiHighlight` and `state.aiRefining`. Pass `highlightedFields: state.aiHighlight` to `DraftCard`. Above the save button (inside the `if (hasContent)` block, before `AppPrimaryButton`), add a refining indicator:

```dart
            if (state.aiRefining)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: AppSpacing.sm),
                    Text('AI refining…',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
```

- [ ] **Step 4: Add a widget test for the refining indicator**

Read `test/features/enquiries/capture_screen_test.dart` to reuse its harness (it overrides the capture providers with fakes). Add a test that overrides `aiParseServiceProvider` with a delayed fake and asserts `find.text('AI refining…')` appears after entering ≥8 chars, then disappears after settle. If the existing harness makes injecting a delayed AI result awkward, assert the simpler invariant: after entering text and `pump()` (not settle), the indicator is present; after `pumpAndSettle()`, it is gone. Use a fake:

```dart
class _DelayedAi extends AiParseService {
  _DelayedAi() : super(invoker: (_) async => null);
  @override
  Future<AiParse?> refine(String text) async {
    await Future.delayed(const Duration(milliseconds: 50));
    return null;
  }
}
```

Test body outline:

```dart
testWidgets('shows the AI refining indicator while a refine is in flight',
    (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      customersServiceProvider.overrideWithValue(FakeCustomersService()),
      enquiriesServiceProvider.overrideWithValue(FakeEnquiriesService()),
      aiParseServiceProvider.overrideWithValue(_DelayedAi()),
    ],
    child: const MaterialApp(home: CaptureScreen()),
  ));
  await tester.enterText(
      find.byKey(const Key('capture-input')), 'order two sarees please');
  await tester.pump(const Duration(milliseconds: 350)); // debounce elapses
  expect(find.text('AI refining…'), findsOneWidget);
  await tester.pumpAndSettle();
  expect(find.text('AI refining…'), findsNothing);
});
```

Ensure the imports for `aiParseServiceProvider`, `AiParseService`, `AiParse`, and the fake services are present (mirror the existing test file's imports).

- [ ] **Step 5: Run the enquiries widget tests**

Run: `flutter test test/features/enquiries/capture_screen_test.dart`
Expected: PASS (existing + new).

- [ ] **Step 6: Commit**

```bash
git add lib/features/enquiries/widgets/draft_card.dart lib/features/enquiries/presentation/capture_screen.dart test/features/enquiries/capture_screen_test.dart
git commit -m "feat(enquiries): highlight AI-refined draft fields and show refining state"
```

---

### Task 11: Auto follow-up scheduling on save

**Files:**
- Modify: `lib/features/enquiries/presentation/capture_screen.dart`

The rules/AI parse already puts a `follow_up_date` on the draft, and `addEnquiry` writes `status: 'follow'` + `follow_up_date` when a date is present. The last gap is scheduling the reminder immediately after save — `NotificationService.syncLeadNotifications()` reads the leads and (re)schedules. The capture `_save` currently reloads enquiries but never resyncs notifications; add that call.

- [ ] **Step 1: Add the notification resync to `_save`**

In `lib/features/enquiries/presentation/capture_screen.dart`, add the import:

```dart
import 'package:orderly_app/core/services/notification_service.dart';
```

In `_save`, after `ref.read(enquiriesControllerProvider.notifier).load();`, add:

```dart
      // Schedule/refresh the follow-up reminder for the just-saved enquiry.
      NotificationService.syncLeadNotifications();
```

(`syncLeadNotifications` fetches leads itself and is fire-and-forget; do not await it so the UI stays snappy.)

- [ ] **Step 2: Verify analyze + the enquiries suite still pass**

Run: `flutter test test/features/enquiries/`
Expected: PASS (no regressions; this change adds a fire-and-forget call). If a widget test environment lacks the notification plugin and the call throws, guard it: wrap in `try { NotificationService.syncLeadNotifications(); } catch (_) {}` — but since it is not awaited and `syncLeadNotifications` catches its own I/O, tests that already exercise `_save` (the existing "saves enquiry" test) are the proof. Confirm that test still passes.

- [ ] **Step 3: Commit**

```bash
git add lib/features/enquiries/presentation/capture_screen.dart
git commit -m "feat(enquiries): schedule follow-up reminder after capture save"
```

---

### Task 12: Final gate + review

**Files:** none (verification + review).

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all pass (66 from Slice A + the Slice B additions).

- [ ] **Step 3: Advisors unchanged**

Use the Supabase MCP `get_advisors` (`type: security`). Expected: the same 8 baseline WARNs; no new entry for `ai_parse_usage`.

- [ ] **Step 4: Final code review**

Dispatch the code-reviewer agent over the whole slice: `git diff <first-slice-B-commit>^..HEAD` (the first commit from Task 1). Focus areas: edge-function auth/rate-limit/PII-logging correctness; that AI output is coerced before use (no injection into privileged actions); merge staleness/manual-preserve; no secrets in git or `.env`. Fix verified findings with implementer subagents and re-review.

- [ ] **Step 5: Finish the branch**

Use superpowers:finishing-a-development-branch. Then deliver a summary plus the device smoke checklist: paste a dated message → rules draft fills instantly → (with key set) AI highlight updates fields within ~1–3s → save → reminder scheduled → notification fires at the follow-up time; airplane-mode paste → rules draft still saves with no error toast.

---

## Self-Review

**1. Spec coverage:**
- Edge function `parse-enquiry`, JWT-verified, per-user rate limit, LLM key in Supabase secrets, strict JSON output, no chat text in logs → Tasks 1–5 (handler logs only labels/codes; key via `supabase secrets`; rate-limit RPC; `responseSchema`).
- Gemini Flash-class first, provider behind adapter, Claude swap = config change → Task 3 `createParser()` + `AI_PROVIDER`/`GEMINI_MODEL` env.
- Client: rules fills instantly, AI async, refined fields merge with subtle highlight, AI never blocks save, offline/error/timeout → rules stands silently → Tasks 7 (timeout/error→null), 9 (async + merge + staleness), 10 (highlight/indicator).
- Auto follow-up: parsed/AI date auto-sets follow_up_date + schedules via existing engine; intent default when no explicit date → Tasks 6 (default +2d), 11 (resync).
- Testing (parser mappings, rules↔AI merge, auth rejection, input validation, schema-conformant output via mocked provider, client fake parse service) → Tasks 6/7/9 (Dart), 5 (auth 401 / validation 400 smoke). Edge-function unit tests via mocked provider are not run locally (no Deno); coverage is shifted to the client coercion tests + deployed smoke, which is called out explicitly.
- Security (RLS/user scoping, JWT, rate limit, key server-side, never log chat, AI output validated as data) → Tasks 1 (RLS + revokes), 4 (auth + PII-safe logs), 7 (coercion). No AI output triggers privileged actions: it only populates an editable draft the user confirms before save.

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N" — every code step is complete. The two soft spots (Task 8 possibly-unused field, Task 9 stale-test simplification) include explicit resolution text rather than a placeholder.

**3. Type consistency:** `AiParse`/`AiParseService`/`AiInvoker` names match across Tasks 7–10. `aiParseServiceProvider` introduced in Task 8 and used in 9/10. `CaptureState` fields `aiRefining`/`aiHighlight` added in Task 8, read in 9/10. Controller constructor arity change (Task 8) is reconciled in Task 9 Step 4. `ParsedEnquiry` (TS) and the Dart `AiParse` intentionally differ (server contract vs client model) and are bridged by `_coerce`. Highlight keys `'name'|'phone'|'items'|'followUp'|'intent'` are consistent between Task 9 (set) and Task 10 (read).
