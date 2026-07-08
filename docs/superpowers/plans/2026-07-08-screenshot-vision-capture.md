# Slice C1 — Screenshot Vision Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a seller attach a chat screenshot on the CaptureScreen; it is parsed by the `parse-enquiry` edge function using Gemini vision (same JSON schema as text), refines the draft exactly like pasted text, and is stored with the saved enquiry.

**Architecture:** Extend the existing `parse-enquiry` edge function to accept an optional base64 image alongside/instead of text and forward it to Gemini as an `inlineData` part — the response schema and client coercion are unchanged. The client's `AiParseService` gains an image parameter; the capture controller gains `attachScreenshot`, which runs the same async refine + merge pipeline used for text. On save, the screenshot is uploaded to a new private storage bucket and its path stored on the lead row. This is the first half of Slice C (share-to-Closr, spec §3 Slice C); native share ingestion (Android intent filter + iOS Share Extension) is a separate later plan (C2).

**Tech Stack:** Supabase Edge Function (Deno/TS) + Gemini `gemini-2.5-flash` vision (`inlineData`), Supabase Storage (private bucket, owner-scoped RLS), Flutter/Dart, `image_picker`, `flutter_image_compress`, Riverpod `StateNotifier`, `supabase_flutter`.

**Prerequisite (already flagged for Slice B, still required):** the `GEMINI_API_KEY` Supabase secret must be set for the live vision path. Without it the function returns 502 and the client silently keeps the rules draft (a screenshot with no extractable text simply yields an empty refine). Everything here is buildable/testable without the key; the live vision smoke (Task 2 Step 5) is deferred until it is set.

## File Structure

**Database:**
- Create `supabase/migrations/0009_enquiry_attachments.sql` — `enquiry-attachments` private bucket + owner-scoped storage policies, `leads.screenshot_url` column, and `source` CHECK extended to allow `'screenshot'` and `'share'`.

**Edge function (redeploy `parse-enquiry`):**
- Modify `supabase/functions/parse-enquiry/schema.ts` — `ParseInput` type; `buildPrompt` handles the image-only case.
- Modify `supabase/functions/parse-enquiry/provider.ts` — `parse(input: ParseInput)`; add an `inlineData` part when an image is present.
- Modify `supabase/functions/parse-enquiry/index.ts` — accept and validate an optional `image: {mime, data}`; require text or image.

**Client:**
- Modify `lib/features/enquiries/data/ai_parse_service.dart` — invoker takes a body map; `refine` gains `image`/`mime`; base64-encodes the image.
- Modify `lib/features/enquiries/controller/capture_provider.dart` — `CaptureState.screenshotPath`/`screenshotBytes`; `attachScreenshot`; `_refine` forwards an optional image.
- Modify `lib/features/enquiries/data/enquiry.dart` — `screenshotUrl` field.
- Modify `lib/features/enquiries/data/enquiries_service.dart` — `uploadScreenshot`; `addEnquiry` accepts `screenshotPath` and persists `screenshot_url`.
- Modify `lib/features/enquiries/presentation/capture_screen.dart` — "Attach screenshot" action (image_picker + compress), thumbnail, pass path to save.

**Tests:**
- Modify `test/features/enquiries/ai_parse_service_test.dart` — image forwarding + body shape.
- Modify `test/features/enquiries/capture_controller_test.dart` — `attachScreenshot` refine/merge; updated `FakeAiParseService` signature.
- Modify `test/features/enquiries/enquiry_test.dart` — `screenshotUrl` parse.
- Modify `test/features/enquiries/capture_screen_test.dart` — attach button present.

---

### Task 1: Storage bucket + lead attachment column (migration 0009)

**Files:**
- Create: `supabase/migrations/0009_enquiry_attachments.sql`

Mirror the proven `product-images` bucket pattern (private, owner-scoped by top folder = user id). Add the column that holds the uploaded object path, and widen the `source` CHECK now so the later share slice needs no further migration.

- [ ] **Step 1: Write the migration**

```sql
-- Private bucket for chat screenshots attached to enquiries, plus the lead
-- column that stores the uploaded object path. Files live under a
-- <user_id>/... prefix so policies scope by the first path folder, exactly
-- like product-images (migration 0003).
insert into storage.buckets (id, name, public)
values ('enquiry-attachments', 'enquiry-attachments', false)
on conflict (id) do nothing;

create policy "enquiry-attachments read own" on storage.objects
  for select using (
    bucket_id = 'enquiry-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "enquiry-attachments write own" on storage.objects
  for insert with check (
    bucket_id = 'enquiry-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "enquiry-attachments update own" on storage.objects
  for update using (
    bucket_id = 'enquiry-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "enquiry-attachments delete own" on storage.objects
  for delete using (
    bucket_id = 'enquiry-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

alter table public.leads
  add column if not exists screenshot_url text;

-- Allow capture sources introduced by the vision + share slices.
alter table public.leads drop constraint leads_source_check;
alter table public.leads add constraint leads_source_check
  check (source in ('dm','paste','product','manual','screenshot','share'));
```

- [ ] **Step 2: Apply via Supabase MCP**

Use `apply_migration` with `project_id: dgviploqkwyuttcdnddq`, `name: enquiry_attachments`, and the SQL above. Expected: `{"success":true}`.

- [ ] **Step 3: Verify the column and constraint**

Use `execute_sql` (`project_id: dgviploqkwyuttcdnddq`):

```sql
select
  (select 1 from information_schema.columns
     where table_name='leads' and column_name='screenshot_url') as has_col,
  (select pg_get_constraintdef(oid) from pg_constraint
     where conname='leads_source_check') as source_check;
```

Expected: `has_col = 1` and `source_check` lists all six values including `screenshot` and `share`.

- [ ] **Step 4: Verify advisors unchanged**

Use `get_advisors` (`type: security`). Expected: the same baseline (9 WARN + 1 INFO from Slice B); no new finding. The storage policies match the existing pattern and add no advisory.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0009_enquiry_attachments.sql
git commit -m "feat(db): enquiry-attachments bucket and lead screenshot_url"
```

---

### Task 2: Edge function vision path

**Files:**
- Modify: `supabase/functions/parse-enquiry/schema.ts`
- Modify: `supabase/functions/parse-enquiry/provider.ts`
- Modify: `supabase/functions/parse-enquiry/index.ts`

Accept an optional image and forward it to Gemini as an `inlineData` part. No local Deno; proof is a successful MCP redeploy + auth smoke. The response schema and coercion are unchanged.

- [ ] **Step 1: Add `ParseInput` and adjust the prompt (schema.ts)**

At the top of `supabase/functions/parse-enquiry/schema.ts`, above `ParsedEnquiry`, add:

```typescript
export interface ParseInput {
  text: string;
  image?: { mimeType: string; data: string }; // data = base64, no prefix
}
```

Replace the existing `buildPrompt` with a version that handles an empty text (image-only) case:

```typescript
export function buildPrompt(text: string, todayIso: string): string {
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
    "",
    hasText ? "Message:" : "Extract from the attached screenshot.",
    hasText ? text : "",
  ].join("\n");
}
```

- [ ] **Step 2: Forward the image to Gemini (provider.ts)**

In `supabase/functions/parse-enquiry/provider.ts`, change the import and the `parse` signature to take `ParseInput`, and add the image part:

Update the import line:

```typescript
import { buildPrompt, ParsedEnquiry, ParseInput, responseSchema } from "./schema.ts";
```

Change the interface:

```typescript
export interface EnquiryParser {
  parse(input: ParseInput): Promise<ParsedEnquiry>;
}
```

Replace the `GeminiParser.parse` body's `contents` construction. The method becomes:

```typescript
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
        throw new Error(`gemini_http_${res.status}`);
      }
      const data = await res.json();
      const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof raw !== "string") throw new Error("gemini_empty");
      try {
        return JSON.parse(raw) as ParsedEnquiry;
      } catch (_) {
        throw new Error("gemini_bad_json");
      }
    } finally {
      clearTimeout(timer);
    }
  }
```

- [ ] **Step 3: Accept and validate the image (index.ts)**

In `supabase/functions/parse-enquiry/index.ts`, add image constants near the top:

```typescript
const MAX_INPUT_CHARS = 4000;
const MAX_IMAGE_B64 = 2_000_000; // ~1.5 MB decoded
const ALLOWED_IMAGE_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
const RATE_MAX = 30;
const RATE_WINDOW_SECONDS = 3600;
```

Replace the input-parsing/validation block (the `let text: unknown; ...` through the `too_long` check) with one that also reads and validates the optional image, and requires at least one input:

```typescript
  // Validate input before consuming a rate-limit slot so malformed requests
  // never burn the user's quota.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }

  const text = typeof body.text === "string" ? body.text : "";
  if (text.length > MAX_INPUT_CHARS) {
    return json({ error: "too_long" }, 413);
  }

  let image: { mimeType: string; data: string } | undefined;
  const rawImage = body.image;
  if (rawImage !== undefined && rawImage !== null) {
    if (
      typeof rawImage !== "object" ||
      typeof (rawImage as Record<string, unknown>).mime !== "string" ||
      typeof (rawImage as Record<string, unknown>).data !== "string"
    ) {
      return json({ error: "bad_request" }, 400);
    }
    const mime = (rawImage as Record<string, string>).mime;
    const dataB64 = (rawImage as Record<string, string>).data;
    if (!ALLOWED_IMAGE_MIME.has(mime)) {
      return json({ error: "unsupported_media" }, 415);
    }
    if (dataB64.length === 0 || dataB64.length > MAX_IMAGE_B64) {
      return json({ error: "bad_request" }, 400);
    }
    image = { mimeType: mime, data: dataB64 };
  }

  if (text.trim().length === 0 && image === undefined) {
    return json({ error: "bad_request" }, 400);
  }
```

Then update the provider call in the final `try` block to pass a `ParseInput`:

```typescript
  try {
    const parser = createParser();
    const result = await parser.parse({ text, image });
    return json(result, 200);
  } catch (e) {
    const label = e instanceof Error ? e.message : "unknown";
    console.error(`parse_failed:${label}`);
    return json({ error: "parse_failed" }, 502);
  }
```

- [ ] **Step 4: Redeploy via Supabase MCP**

Use `deploy_edge_function` (`project_id: dgviploqkwyuttcdnddq`, `name: parse-enquiry`, `entrypoint_path: index.ts`, `verify_jwt: true`) with all four files (`index.ts`, `provider.ts`, `schema.ts`, `../_shared/cors.ts`) at their current repo contents. A successful deploy (new version) is the typecheck proof.

- [ ] **Step 5: Smoke test**

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  "https://dgviploqkwyuttcdnddq.supabase.co/functions/v1/parse-enquiry" \
  -H "Content-Type: application/json" -d '{"text":"hi"}'
```
Expected: `401` (no auth). Live vision (image with a valid JWT + `GEMINI_API_KEY`) is **deferred, needs user** — record it.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/parse-enquiry/schema.ts supabase/functions/parse-enquiry/provider.ts supabase/functions/parse-enquiry/index.ts
git commit -m "feat(edge): parse-enquiry accepts a screenshot for vision extraction"
```

---

### Task 3: Client AiParseService image support

**Files:**
- Modify: `lib/features/enquiries/data/ai_parse_service.dart`
- Test: `test/features/enquiries/ai_parse_service_test.dart`

Change the injectable transport to take a body map (so tests can assert the image is forwarded), and add an optional image to `refine` that is base64-encoded into `{mime, data}`. Coercion is unchanged.

- [ ] **Step 1: Write the failing tests**

Replace the `withJson` helper at the top of `test/features/enquiries/ai_parse_service_test.dart` (it currently builds an invoker of shape `(text) async => json`) with a body-based one, and add forwarding tests. New helper + tests to add:

```dart
// at top of main(), replacing the existing withJson helper
Map<String, dynamic>? lastBody;
AiParseService withJson(Map<String, dynamic>? json, {Duration? delay}) {
  return AiParseService(
    timeout: const Duration(milliseconds: 100),
    invoker: (body) async {
      lastBody = body;
      if (delay != null) await Future.delayed(delay);
      return json;
    },
  );
}
```

Add these tests inside `main()`:

```dart
test('forwards the text in the request body', () async {
  await withJson({'confidence': 0.5}).refine('order 2 sarees');
  expect(lastBody!['text'], 'order 2 sarees');
  expect(lastBody!.containsKey('image'), isFalse);
});

test('base64-encodes an attached image into the body', () async {
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  await withJson({'confidence': 0.5})
      .refine('', image: bytes, mime: 'image/png');
  final image = lastBody!['image'] as Map<String, dynamic>;
  expect(image['mime'], 'image/png');
  expect(image['data'], base64Encode(bytes));
});
```

Add the imports the tests need at the top of the file:

```dart
import 'dart:convert';
import 'dart:typed_data';
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/enquiries/ai_parse_service_test.dart`
Expected: FAIL — the old `withJson` invoker signature `(text)` no longer matches, and `refine` has no `image` parameter.

- [ ] **Step 3: Update the service**

In `lib/features/enquiries/data/ai_parse_service.dart`, add imports at the top:

```dart
import 'dart:convert';
import 'dart:typed_data';
```

Change the typedef and the default invoker to use a body map, and add the image params to `refine`:

```dart
typedef AiInvoker = Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> body);
```

```dart
  static Future<Map<String, dynamic>?> _defaultInvoke(
      Map<String, dynamic> body) async {
    final res = await Supabase.instance.client.functions
        .invoke('parse-enquiry', body: body);
    final data = res.data;
    return data is Map<String, dynamic> ? data : null;
  }

  Future<AiParse?> refine(
    String text, {
    Uint8List? image,
    String mime = 'image/jpeg',
  }) async {
    final body = <String, dynamic>{
      'text': text,
      if (image != null)
        'image': {'mime': mime, 'data': base64Encode(image)},
    };
    try {
      final json = await _invoke(body).timeout(_timeout);
      if (json == null) return null;
      return _coerce(json);
    } catch (_) {
      return null;
    }
  }
```

(The `_coerce` method is unchanged.)

- [ ] **Step 4: Run to verify all pass**

Run: `flutter test test/features/enquiries/ai_parse_service_test.dart`
Expected: PASS (existing coercion/timeout tests + the two new forwarding tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/data/ai_parse_service.dart test/features/enquiries/ai_parse_service_test.dart
git commit -m "feat(enquiries): AiParseService forwards an optional screenshot"
```

---

### Task 4: Controller attachScreenshot + image refine

**Files:**
- Modify: `lib/features/enquiries/controller/capture_provider.dart`
- Test: `test/features/enquiries/capture_controller_test.dart`

`attachScreenshot(bytes, path)` stores the screenshot on the state and runs the same async refine/merge pipeline, passing the image to the AI. The `_refine` method gains an optional image; `setText` still calls it text-only.

- [ ] **Step 1: Write the failing tests**

In `test/features/enquiries/capture_controller_test.dart`, first update `FakeAiParseService` to the new `refine` signature and record the image, then add attach tests. Replace the existing `FakeAiParseService` class:

```dart
class FakeAiParseService extends AiParseService {
  FakeAiParseService(this._result, {this.delay = Duration.zero})
      : super(invoker: (_) async => null);
  final AiParse? _result;
  final Duration delay;
  Uint8List? lastImage;

  @override
  Future<AiParse?> refine(String text,
      {Uint8List? image, String mime = 'image/jpeg'}) async {
    lastImage = image;
    if (delay != Duration.zero) await Future.delayed(delay);
    return _result;
  }
}
```

Add the import at the top of the file:

```dart
import 'dart:typed_data';
```

Add these tests inside `main()`:

```dart
test('attachScreenshot stores the shot and refines with the image', () async {
  final fakeAi = FakeAiParseService(const AiParse(
    name: 'Priya',
    intent: 'order',
    type: 'order',
    confidence: 0.9,
  ));
  final c = makeContainer(
      FakeCustomersService(), FakeEnquiriesService(), ai: fakeAi);
  final controller = c.read(captureControllerProvider.notifier);

  final bytes = Uint8List.fromList([9, 8, 7]);
  controller.attachScreenshot(bytes, path: '/tmp/shot.jpg');
  await Future<void>.delayed(Duration.zero);

  final state = c.read(captureControllerProvider);
  expect(state.screenshotPath, '/tmp/shot.jpg');
  expect(state.screenshotBytes, bytes);
  expect(fakeAi.lastImage, bytes); // image reached the AI service
  expect(state.draft.name, 'Priya'); // merge ran
  expect(state.aiRefining, isFalse);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/enquiries/capture_controller_test.dart`
Expected: FAIL — `attachScreenshot` and `CaptureState.screenshotPath`/`screenshotBytes` do not exist.

- [ ] **Step 3: Add state fields**

In `lib/features/enquiries/controller/capture_provider.dart`, add an import:

```dart
import 'dart:typed_data';
```

Add two fields to `CaptureState` (constructor param, finals, `copyWith`). Constructor param (after `attachedItem`):

```dart
    this.screenshotPath,
    this.screenshotBytes,
```

Finals (after `attachedItem`):

```dart
  /// Local path + bytes of an attached chat screenshot (null when none).
  final String? screenshotPath;
  final Uint8List? screenshotBytes;
```

`copyWith` params:

```dart
    String? screenshotPath,
    Uint8List? screenshotBytes,
```

`copyWith` body (before `aiRefining:`):

```dart
        screenshotPath: screenshotPath ?? this.screenshotPath,
        screenshotBytes: screenshotBytes ?? this.screenshotBytes,
```

- [ ] **Step 4: Generalize `_refine` and add `attachScreenshot`**

Change `_refine`'s signature to accept an optional image and forward it. Update its first line:

```dart
  Future<void> _refine(String text, int token,
      {Uint8List? image, String mime = 'image/jpeg'}) async {
    final ai = await _ai.refine(text, image: image, mime: mime);
    if (!mounted || token != _parseToken) return; // superseded
```

(The rest of `_refine` — the merge — is unchanged.)

Add `attachScreenshot` (place it after `setText`):

```dart
  void attachScreenshot(Uint8List bytes,
      {required String path, String mime = 'image/jpeg'}) {
    _parseToken++;
    final token = _parseToken;
    state = state.copyWith(
      screenshotPath: path,
      screenshotBytes: bytes,
      aiRefining: true,
      aiHighlight: const {},
    );
    _refine(state.draft.raw, token, image: bytes, mime: mime);
  }
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/features/enquiries/capture_controller_test.dart`
Expected: PASS (all, including the new attach test).

- [ ] **Step 6: Commit**

```bash
git add lib/features/enquiries/controller/capture_provider.dart test/features/enquiries/capture_controller_test.dart
git commit -m "feat(enquiries): attachScreenshot runs the refine pipeline on an image"
```

---

### Task 5: Persist the screenshot on save

**Files:**
- Modify: `lib/features/enquiries/data/enquiry.dart`
- Modify: `lib/features/enquiries/data/enquiries_service.dart`
- Test: `test/features/enquiries/enquiry_test.dart`

Add the `screenshotUrl` model field and an upload path. `addEnquiry` gains an optional `screenshotPath`: when present it uploads to the `enquiry-attachments` bucket (mirroring `ProductsService.uploadImage`) and stores the object path in `leads.screenshot_url`.

- [ ] **Step 1: Write the failing test (model field)**

In `test/features/enquiries/enquiry_test.dart`, add:

```dart
test('fromMap reads screenshot_url', () {
  final e = Enquiry.fromMap({
    'id': 'e1',
    'screenshot_url': 'uid/123.jpg',
  });
  expect(e.screenshotUrl, 'uid/123.jpg');
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/enquiries/enquiry_test.dart`
Expected: FAIL — `screenshotUrl` getter does not exist.

- [ ] **Step 3: Add the model field**

In `lib/features/enquiries/data/enquiry.dart`, add the field to the class. Add the constructor param, the final, and the `fromMap` read. Constructor param (place near `message`):

```dart
    this.screenshotUrl,
```

Final (near `message`):

```dart
  final String? screenshotUrl;
```

In `fromMap`, add the assignment (mirroring how `message` is read):

```dart
      screenshotUrl: map['screenshot_url'] as String?,
```

- [ ] **Step 4: Add upload + persist in the service**

In `lib/features/enquiries/data/enquiries_service.dart`, add imports at the top (if not present):

```dart
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
```

Add an upload helper to `EnquiriesService` (mirrors `ProductsService.uploadImage`):

```dart
  static const _attachmentsBucket = 'enquiry-attachments';

  /// Compresses and uploads a screenshot to the private attachments bucket,
  /// returning the stored object path (scoped under the user's folder).
  Future<String> uploadScreenshot(String localPath) async {
    final bytes = await FlutterImageCompress.compressWithFile(
      localPath,
      minWidth: 1280,
      minHeight: 1280,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    final data = bytes ?? await File(localPath).readAsBytes();
    final path =
        '$_userId/${DateTime.now().millisecondsSinceEpoch}_${data.length}.jpg';
    await _client.storage.from(_attachmentsBucket).uploadBinary(
          path,
          Uint8List.fromList(data),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }
```

(The service exposes the client as `_client` — `SupabaseClient get _client => Supabase.instance.client;`.)

Add the `dart:io` import for the `File` fallback:

```dart
import 'dart:io';
```

Add a `screenshotPath` parameter to `addEnquiry` and persist the uploaded path. Update the signature and the insert map. The new signature:

```dart
  Future<Enquiry> addEnquiry({
    required String customerId,
    String? productId,
    required String source,
    String? message,
    String? intent,
    DateTime? followUpDate,
    String? screenshotPath,
  }) async {
    final screenshotUrl = (screenshotPath != null && screenshotPath.isNotEmpty)
        ? await uploadScreenshot(screenshotPath)
        : null;
    final row = await _client
        .from('leads')
        .insert({
          'user_id': _userId,
          'customer_id': customerId,
          'product_id': ?productId,
          'source': source,
          if (message != null && message.isNotEmpty) 'message': message,
          'intent': ?intent,
          'screenshot_url': ?screenshotUrl,
          'status': followUpDate != null ? 'follow' : 'new',
          if (followUpDate != null)
            'follow_up_date': followUpDate.toIso8601String(),
          'activities': [
            {
              'type': 'created',
              'note': 'Enquiry captured',
              'time': DateTime.now().toIso8601String(),
            }
          ],
        })
        .select(_selectWithJoins)
        .single();
    return Enquiry.fromMap(row);
  }
```

Note: the existing methods reach Supabase via `_client` (`SupabaseClient get _client => Supabase.instance.client;`) — the code above already uses `_client`. The insert map is identical to the current `addEnquiry` plus the `screenshot_url` line.

- [ ] **Step 5: Wire the capture save to pass the path**

In `lib/features/enquiries/controller/capture_provider.dart`, in `save()`, pass the screenshot path to `addEnquiry`. Update the `addEnquiry` call in the enquiry branch:

```dart
      await _enquiries.addEnquiry(
        customerId: customer.id!,
        productId: state.attachedProductId,
        source: state.screenshotPath != null ? 'screenshot' : source,
        message: draft.raw.trim(),
        intent: draft.intent,
        followUpDate: draft.followUpDate,
        screenshotPath: state.screenshotPath,
      );
```

The `FakeEnquiriesService` in tests must accept the new named parameter. In `test/features/enquiries/capture_controller_test.dart`, update its `addEnquiry` override signature to include `String? screenshotPath,` (it can ignore the value). Update the override:

```dart
  @override
  Future<Enquiry> addEnquiry({
    required String customerId,
    String? productId,
    required String source,
    String? message,
    String? intent,
    DateTime? followUpDate,
    String? screenshotPath,
  }) async {
    enquiries.add({
      'customer_id': customerId,
      'product_id': productId,
      'source': source,
      'status': followUpDate != null ? 'follow' : 'new',
    });
    return Enquiry.fromMap({'id': 'e-new', 'customer_id': customerId});
  }
```

- [ ] **Step 6: Run the enquiries suite**

Run: `flutter test test/features/enquiries/`
Expected: PASS (model test + no regressions; the controller/screen fakes now match the widened `addEnquiry`).

- [ ] **Step 7: Commit**

```bash
git add lib/features/enquiries/data/enquiry.dart lib/features/enquiries/data/enquiries_service.dart lib/features/enquiries/controller/capture_provider.dart test/features/enquiries/enquiry_test.dart test/features/enquiries/capture_controller_test.dart
git commit -m "feat(enquiries): upload and persist the attached screenshot on save"
```

---

### Task 6: CaptureScreen attach-screenshot UI

**Files:**
- Modify: `lib/features/enquiries/presentation/capture_screen.dart`
- Test: `test/features/enquiries/capture_screen_test.dart`

Add an "Attach screenshot" button next to Paste/Speak that picks an image, compresses it, and calls `attachScreenshot`; show a thumbnail when one is attached. `image_picker` cannot be driven in a widget test, so the test only asserts the button is present (the pick→refine path is device-smoke).

- [ ] **Step 1: Write the failing test**

In `test/features/enquiries/capture_screen_test.dart`, add:

```dart
testWidgets('offers an attach-screenshot action', (tester) async {
  await tester.pumpWidget(wrap(const CaptureScreen(), FakeEnquiriesService()));
  expect(find.text('Screenshot'), findsOneWidget);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/enquiries/capture_screen_test.dart`
Expected: FAIL — no `Screenshot` button yet.

- [ ] **Step 3: Add the picker + thumbnail**

In `lib/features/enquiries/presentation/capture_screen.dart`, add imports:

```dart
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
```

Add a picker method to `_CaptureScreenState`:

```dart
  Future<void> _attachScreenshot() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final compressed = await FlutterImageCompress.compressWithFile(
      picked.path,
      minWidth: 1280,
      minHeight: 1280,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    final bytes = compressed ?? await picked.readAsBytes();
    if (!mounted) return;
    ref.read(captureControllerProvider.notifier).attachScreenshot(
          Uint8List.fromList(bytes),
          path: picked.path,
        );
  }
```

Add the button to the Paste/Speak `Row` (after the Speak `TextButton.icon`):

```dart
              TextButton.icon(
                onPressed: _attachScreenshot,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Screenshot'),
              ),
```

Show a thumbnail inside the `if (hasContent) ...[` block, immediately before `DraftCard(...)`, when a screenshot is attached:

```dart
            if (state.screenshotBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.memory(
                  state.screenshotBytes!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
```

Also make `hasContent` account for an attached screenshot so the draft card + save button appear even before any text parse. Update the `hasContent` line:

```dart
    final hasContent = !draft.isEmpty ||
        state.attachedProductId != null ||
        state.screenshotBytes != null;
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/enquiries/capture_screen_test.dart`
Expected: PASS (button present; existing tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add lib/features/enquiries/presentation/capture_screen.dart test/features/enquiries/capture_screen_test.dart
git commit -m "feat(enquiries): attach a chat screenshot from the capture screen"
```

---

### Task 7: Final gate + review

**Files:** none (verification + review).

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all pass (83 from Slice B + the additions here).

- [ ] **Step 3: Advisors unchanged**

Use the Supabase MCP `get_advisors` (`type: security`). Expected: the Slice B baseline (9 WARN + 1 INFO); no new finding for the bucket/column.

- [ ] **Step 4: Final code review**

Dispatch the code-reviewer agent over the whole slice (`git diff <Task-1-commit>^..HEAD`). Focus: edge-function image validation (size/mime, still auth+rate-limited, no PII in logs); AI image forwarding; that a screenshot is uploaded to an owner-scoped path and its object path (not a public URL) is stored; the `source` value is a valid enum; no unbounded base64 in memory. Fix verified findings with implementer subagents and re-review.

- [ ] **Step 5: Finish the branch**

Use superpowers:finishing-a-development-branch. Then deliver a summary + device smoke checklist: FAB → CaptureScreen → Screenshot → pick a chat screenshot → thumbnail shows → (with `GEMINI_API_KEY` set) draft fields fill from the image within a few seconds → save → open the enquiry → screenshot persisted; airplane-mode attach still saves the screenshot with an empty/rules draft and no error toast.

---

## Self-Review

**1. Spec coverage (Slice C, screenshot half):**
- "Shared screenshot → attached to the enquiry and parsed via the same edge function using vision (image in, same JSON schema out)" → Task 2 (edge `inlineData`, unchanged `responseSchema`), Task 3 (client forwards image), Task 4 (refine/merge), Task 5 (persist on the lead). The *share-intent* delivery (Android filter / iOS Share Extension, cold/warm start) is explicitly out of this plan and belongs to C2 — noted in the header.
- Same rules + AI pipeline → `attachScreenshot` reuses `_refine`/merge (Task 4); the rules draft still stands when the image yields nothing (AI returns null → silent, Task 3 unchanged coercion).

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to". Every step has concrete code. The one conditional instruction (Task 5 Step 4 "confirm the client getter name is `supabase`") gives the exact fallback action rather than deferring a decision.

**3. Type consistency:** `ParseInput` (schema.ts) is produced in index.ts and consumed by `provider.parse` (Task 2). Client `AiInvoker` is a body map in Task 3 and matched by `FakeAiParseService`/`withJson` (Tasks 3–4). `refine(text, {image, mime})` signature matches across service (Task 3), `_refine` (Task 4), and both fakes. `screenshotPath`/`screenshotBytes` added in Task 4 and read in Tasks 5–6. `screenshotUrl` model field (Task 5) reads `screenshot_url`, the column added in Task 1. `addEnquiry`'s new `screenshotPath` param (Task 5) matches the call site (Task 5 Step 5) and both fakes. Storage bucket id `enquiry-attachments` is identical in the migration (Task 1) and `uploadScreenshot` (Task 5).
