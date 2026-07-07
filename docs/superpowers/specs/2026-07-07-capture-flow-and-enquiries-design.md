# Closr — Automated Capture Flow + Enquiries Rebuild (Design Spec)

Extends the core pipeline spec (`2026-07-04-closr-social-seller-pipeline-design.md`). Pulls stage 3 (customers) forward and merges it with a rebuilt, automation-first capture flow. Supersedes the legacy add-entry path.

## 1. Problem

- The AI paste flow (`WhatsAppInputScreen`) is unreachable: its only entry point, `AddEntrySelector`, is dead code. The FAB opens the legacy manual `AddEntryScreen` as a bottom sheet.
- "AI" today is keyword matching (`contains("order")`, `contains("tomorrow")`).
- Legacy capture writes raw maps to `leads` where `status: "closed"` impersonates an order. No customer entity is used, though `customers` and `leads.customer_id` / `orders.customer_id` already exist in the schema (migration `0001_core_schema.sql`).
- Capture is the app's wedge; it must be the fastest, most automated path in the product.

## 2. Goals

1. One capture surface, paste-first, reachable from the FAB, that turns a WhatsApp chat into a linked customer + enquiry (or order) in one tap.
2. Real AI extraction via a server-side LLM, layered on an instant local rules parse — AI never blocks saving and the flow works offline.
3. Share-to-Closr from WhatsApp on **both** Android and iOS.
4. Auto follow-up scheduling from parsed intent/date, reusing the existing notification engine.
5. Enquiries (renamed from Leads) rebuilt on the new data model and design system.
6. Delete the legacy capture path entirely.

### Non-goals (this effort)

- Dashboard and Orders full redesign (stages 4 and 7 own those).
- Re-marketing / broadcast drafts (later Trudy phase).
- Customer profile screen with full history (follows in a later slice; this effort only creates/links customers).

## 3. Slices (each ships working software, in order)

### Slice A — Capture core

**CaptureScreen** (full screen, replaces `AddEntryScreen` + `WhatsAppInputScreen` + `AddEntrySelector`):

- Paste box front and center, autofocused; "Paste" button reads the clipboard. Mic input kept.
- Debounced rules parse (improved `message_parser.dart`) fills a live **draft card**: customer name, phone, items, intent, type (`enquiry` | `order`), suggested follow-up date. Every field tappable to edit.
- Manual entry = same screen, same draft card, no paste required.
- Save button adapts to parsed type: "Save enquiry" (default) or "Create order" (writes `orders` + `order_items`).
- Optional product attachment; Catalog product detail gains "Create enquiry" which opens CaptureScreen with the product pre-attached.

**Customer resolution on save:**

- Phone present + matches existing customer (per-user unique) → link.
- Phone present, no match → create customer with name + phone.
- No phone → create customer by name only (mergeable later). Enquiry/order rows always carry `customer_id`.

**Enquiries rebuild:**

- Rename Leads → Enquiries across UI and code (`features/enquiries/`).
- Typed models + service + Riverpod controller following the catalog feature's pattern (auth-scoped providers, optimistic updates, `AsyncValue`).
- Screen: follow-up buckets (Overdue / Today / Upcoming / New), search, cards showing customer, product thumbnail when attached, intent pill, follow-up chip.
- Detail: convert-to-order (reserves a unique piece as `booked`), reschedule follow-up, one-tap WhatsApp/call.
- Existing notification engine (overdue/today buckets, once-per-day dedupe, reschedule-on-change) kept and rewired to the typed data layer.

**Navigation/cleanup:**

- Tabs: Home · Enquiries · Orders · Catalog. FAB: Catalog tab → add piece; other tabs → CaptureScreen.
- Delete `add_entry_selector.dart`, `add_entry_screen.dart`, `whatsapp_input_screen.dart`, `entry_detail_screen.dart` once replacements land.

### Slice B — AI extraction + auto follow-up

**Edge function `parse-enquiry` (Supabase):**

- JWT-verified; per-user rate limit; LLM API key in Supabase secrets.
- Input: raw chat text (later: image). Output: strict JSON — `customer_name`, `phone`, `items[{name, qty, price}]`, `intent`, `follow_up_date`, `type: enquiry|order`, `confidence`.
- Model: **Gemini Flash-class initially** (cheap, fast, vision-capable); planned migration to Claude later. The function isolates the provider behind a small adapter (prompt + JSON schema + one `parse(text|image)` call) so switching provider is a config/secret change, not a client change. Client only ever sees the JSON schema. No chat text in function logs (PII).

**Client behavior:**

- Rules parse fills the draft instantly → AI call fires async → refined fields merge in with a subtle highlight. AI never blocks save. Offline/error/timeout → rules result stands silently.

**Auto follow-up:**

- Parsed/AI date auto-sets `follow_up_date` and schedules the reminder through the existing engine.
- Intent defaults when no explicit date (e.g. "will confirm later" → +2 days). User can change before/after save.

### Slice C — Share-to-Closr (Android + iOS)

- Share-intent package (e.g. `receive_sharing_intent`): Android intent filter for text + images; iOS Share Extension (native target + App Group).
- Shared text → app opens directly into CaptureScreen prefilled → same rules + AI pipeline.
- Shared screenshot → attached to the enquiry and parsed via the same edge function using vision (image in, same JSON schema out).
- Cold start and warm start both handled (initial shared media + stream).

## 4. Data model

No new tables. Uses existing `customers`, `leads` (`customer_id`, `product_id`, `follow_up_date`, `intent`, `status`), `orders`, `order_items` from `0001_core_schema.sql`. Possible small migration if a needed column is missing (verify at plan time); RLS policies already cover all tables.

## 5. Error handling

- Clipboard empty / unparseable text → draft card stays empty, manual fields available; never a dead end.
- Edge function failure/timeout (>3s) → keep rules result, no error toast (silent degradation); log to console in debug only.
- Customer dedupe conflict (same phone, different name) → link to existing customer, show name inline so the user can correct.
- Share intent with unsupported payload → open CaptureScreen empty with a short notice.
- Order save failure mid-way → no partial writes (insert order + items via single RPC or transactional path); surface retry snackbar.

## 6. Testing

- Unit: parser mappings (intent, dates, items), customer dedupe logic, rules↔AI draft merge.
- Controller: capture save paths (enquiry / order / customer create-or-link), enquiries buckets, convert-to-order booking.
- Widget: CaptureScreen draft card, Enquiries screen buckets/search, adaptive save button.
- Edge function: auth rejection, input validation, schema-conformant output (mock Anthropic); client tests use a fake parse service.

## 7. Security

- RLS on all tables (already in place); every query scoped by `user_id`.
- Edge function verifies JWT, rate-limits per user, keeps the LLM API key server-side, never logs chat content.
- AI output is data, not instructions: parsed fields go through the same validation as manual input; no model output triggers privileged actions.

## 8. Definition of done (per slice)

Slice ships when: `flutter analyze` clean (baseline exceptions only), all tests green, code-reviewed, legacy files deleted (Slice A), device smoke test of the capture path passes.
