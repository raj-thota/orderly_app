# Closr for Social Sellers — Core Pipeline + Invoicing (Design Spec)

**Date:** 2026-07-04
**Status:** Draft for review
**Slice:** Phase 1 of the product roadmap — the core pipeline plus invoicing, built production-grade.

---

## 1. Overview

Closr is a Flutter + Supabase mobile app that helps small businesses turn conversations into orders. This spec covers the first buildable slice: the **complete sell-to-paid pipeline**, sharpened for one niche and shipped as a production-grade app on Google Play and the App Store.

### Target user (niche)

Online sellers who run their business on **Instagram and WhatsApp** — saree sellers, boutique resellers, and similar small product sellers. They are typically phone-first, non-technical, often home-based. Their catalog is **photos**, their storefront is DMs and WhatsApp status, and their orders are shipped by courier and paid by UPI.

### The core job

Turn scattered DM enquiries into **booked, paid, and shipped orders** — with follow-ups that never slip and receipts sent over WhatsApp in one tap.

### Positioning / wedge

The market for generic small-business invoicing (Vyapar, Khatabook, myBillBook, Zoho) is crowded and dominated. Those tools **bill** well but do not **chase** well, and they do not understand the social-seller workflow (photo catalog, unique pieces, booking, UPI, courier tracking, re-marketing to past buyers).

- **Hero of the product** = the chase + WhatsApp flow (enquiry → booking → payment → shipping → re-market).
- **Invoicing** = the closing step, kept lean and clean, not the headline.
- **Distribution advantage** = WhatsApp-native; the customer never installs anything.

---

## 2. Goals and non-goals

### Goals (this slice)

1. Replace the leads-only data model with a real model: customers, products (image-first), leads/enquiries, orders, order items, payments.
2. Image-first catalog supporting both **unique one-off pieces** (booking, sold state) and **stocked items** (quantity on hand).
3. Enquiry → order pipeline with follow-ups (reuse existing notification engine), booking that reserves a unique piece, order status including shipping/tracking.
4. Payments: manual paid/partial/advance tracking, **UPI collect (QR + deep link)**, payment-proof screenshots, dues roll-up.
5. On-demand PDF receipt/invoice, **GST optional** (shown only if the business sets a GSTIN), UPI QR embedded, shared to WhatsApp. No PDF storage — regenerated from order data.
6. Light "Trudy" automation: suggested next actions, drafted WhatsApp messages, a daily brief, and re-marketing to past buyers.
7. Premium, photo-forward UI built on a real design system (tokens + reusable component kit), replacing today's scattered inline styles.
8. Production-grade security (RLS everywhere, private storage, secrets discipline) and store-readiness for Play + App Store.

### Non-goals (deferred to later phases)

- Full LLM-based message parsing (a later "Smart Trudy" phase). This slice uses rules + templates; LLM stays optional and off the critical path.
- True automated WhatsApp sending via the WhatsApp Cloud API (needs Meta Business approval + cost). This slice uses one-tap prefilled deep-links (`wa.me` / share sheet).
- Payment gateway / card processing. UPI deep-link only (keeps PCI scope out).
- Shareable public catalog link / web storefront (future phase).
- Multi-user / staff accounts, multi-currency (currency fixed to INR for v1).

---

## 3. Decisions locked (from design discussion)

| Decision | Choice |
|---|---|
| Existing data | Still in development — **clean rebuild**, no migration needed |
| Inventory model | **Both** unique one-off pieces and stocked items (product-level `is_unique` toggle) |
| GST on invoices | **Optional** — driven by whether the business profile has a GSTIN |
| Payments | Manual paid/partial/advance **plus UPI collect now** (QR + deep-link), proof screenshots |
| Niche | **Instagram/WhatsApp social sellers** (sarees, boutique, small products) |
| Automation stance | Semi-auto, human-in-the-loop — Trudy drafts, seller taps send |
| UI/UX | Premium, photo-forward, on a tokenized design system |
| Supabase | Direct access via MCP — schema applied as reviewable migrations |
| Distribution | Production apps for Google Play + Apple App Store |
| Currency | INR |

---

## 4. Data model

All tables live in Supabase Postgres, are scoped by `user_id`, and have **Row Level Security enabled with deny-by-default policies** (see §10). Snapshots are used on order items so historical documents stay correct when products change.

### `business_profile` (one row per user)
- `id`, `user_id`
- `name`, `logo_url` (nullable), `address`, `phone`, `email` (nullable)
- `upi_id`, `upi_name` — for UPI collect + QR
- `gstin` (nullable — presence drives GST display), `default_gst_rate`
- `invoice_prefix`, `next_invoice_number` (atomic increment for sequential numbering)
- `currency` (default `INR`)
- `created_at`, `updated_at`

### `customers`
- `id`, `user_id`
- `name`, `phone` (unique per user — dedupe key)
- `email` (nullable), `address` (nullable — used for shipping), `notes` (nullable)
- `tags` (text[] — for re-marketing segments)
- `created_at`, `updated_at`

### `products`
- `id`, `user_id`
- `name`, `description` (nullable), `sku` (nullable)
- `images` (text[] — Supabase Storage paths; image-first)
- `price`, `unit` (pc/kg/box/…), `gst_rate` (nullable)
- `is_unique` (bool) — one-off piece vs stocked
- `piece_status` (available / booked / sold — used when `is_unique`)
- `qty_on_hand` (int — used when not `is_unique`)
- `active` (bool)
- `created_at`, `updated_at`

### `leads` (surfaced in-app as "Enquiries")
- `id`, `user_id`
- `customer_id` (FK → customers)
- `product_id` (nullable FK — the piece they asked about)
- `source` (dm / paste / product / manual)
- `message` (nullable — original enquiry text)
- `intent`, `status` (new / follow / won / lost)
- `follow_up_date`, `follow_up_note` (nullable)
- `activities` (jsonb — timeline, same shape as today)
- `created_at`, `updated_at`

### `orders`
- `id`, `user_id`
- `customer_id` (FK), `lead_id` (nullable FK — origin enquiry)
- `order_number` (sequential, human-friendly)
- `status` (pending / packed / shipped / delivered)
- Shipping (nullable columns, queryable): `courier`, `tracking_no`, `shipped_at`
- `payment_status` (unpaid / partial / paid), computed from payments
- `subtotal`, `tax_total`, `grand_total`
- `invoice_number` (nullable — assigned when an invoice is first generated)
- `notes` (nullable), `delivered_at` (nullable)
- `created_at`, `updated_at`

### `order_items`
- `id`, `order_id` (FK)
- `product_id` (nullable FK)
- **Snapshots:** `name`, `image_url`, `unit_price`, `gst_rate`
- `qty`, `line_total`

### `payments`
- `id`, `order_id` (FK), `user_id`
- `amount`, `method` (upi / cash / other)
- `proof_image_url` (nullable — Storage path to a UPI screenshot)
- `paid_at`, `created_at`

Supports advance + balance: multiple payment rows per order; `orders.payment_status` and dues are derived from the sum of payments versus `grand_total`.

### Relationships (summary)
- A **customer** has many enquiries and many orders.
- An **enquiry** optionally references one product and may convert into one order.
- An **order** has many order items and many payments; it belongs to one customer.
- Booking a unique product sets `piece_status = booked`; delivery/sale sets `sold`.

---

## 5. Storage

Supabase Storage, **private buckets** with per-user access policies (users can only read/write their own files). Images referenced by path; the app fetches **short-lived signed URLs** for display rather than exposing public URLs.

- `product-images` — catalog photos (compressed on upload).
- `payment-proofs` — UPI/payment screenshots.

Invoice PDFs are **not** stored — they are generated client-side on demand and regenerable from order data.

---

## 6. Pipeline and screens

```
📸 Catalog → Share → Enquiry → BOOK (reserve piece) → Collect (UPI/partial) → Ship + track → Delivered → Receipt → Re-market
```

### Catalog
- Image-first grid that feels like Instagram. Add a product by snapping/uploading a photo + price.
- Unique piece → shows Available / Booked / Sold pill; booking prevents double-sell.
- Stocked item → shows quantity on hand.
- From a product: "Create enquiry" → pick or create a customer.

### Enquiries (leads)
- Create product-first (default) or by pasting a DM (rules-based fill; LLM optional/off critical path).
- Keep the existing follow-up notification engine as-is (overdue/today buckets, once-per-day dedupe, reschedule on change).
- Convert enquiry → order; if a unique product is attached, reserve it (`booked`).

### Orders
- Adapt the existing item editor to the new schema (with product snapshots).
- Status: pending → packed → shipped → delivered.
- Shipping: enter courier + tracking number → one-tap share tracking to the customer over WhatsApp.

### Payments
- Mark paid / partial / advance; multiple payments per order.
- **UPI collect:** generate a `upi://pay?pa=<upi_id>&pn=<upi_name>&am=<amount>&tn=<ref>` deep-link and QR from the seller's UPI ID.
- Attach a payment-proof screenshot.
- Dues (grand_total − paid) roll up to the dashboard.

### Receipt / Invoice
- Client-side PDF (`pdf` + `printing`).
- GST lines (CGST + SGST, intra-state 50/50 split for v1) **only when a GSTIN is set**; otherwise a clean receipt.
- UPI QR embedded so the customer can pay from the document.
- Sequential invoice number via atomic increment on `business_profile`; number stored on the order.
- Shared to WhatsApp / saved via the native share sheet. Regenerable anytime.

### Customer profile
- Full history (enquiries + orders), outstanding dues, one-tap reorder / WhatsApp / call.

### Dashboard (Home)
- Revenue (today / week / month), pipeline counts, total dues, top pieces, enquiry→order conversion %.

### Trudy (light automation this slice)
- Suggested next action per enquiry (rules).
- Drafts WhatsApp messages for follow-up, quote, and receipt (customer name + items + total) — one tap to send.
- Daily brief card (follow-ups due · dues · yesterday's sales) — reuse notification buckets.
- Re-market to past buyers ("new stock") — drafted broadcast by tag/segment.

### Navigation
Four tabs for simplicity: **Home · Enquiries · Orders · Catalog**. FAB = context add (piece / enquiry / paste). Customers reached via search + tap-through from enquiries/orders.

---

## 7. UI/UX — premium design system

Today the app hardcodes colors and spacing inline (e.g. `Color(0xFF6C4ED9)` repeated across files). "Premium" requires a real system, not just prettier screens.

### Design tokens (central `theme/`)
- Color: primary + surfaces + semantic (success / warning / danger) + money-green / dues-red.
- Type scale, spacing scale (4 / 8 / 12 / 16 / 24), radius (16–24), soft elevation.
- Structured so dark mode is essentially free.

### Component kit (build once, reuse everywhere)
`AppButton`, `AppCard`, `StatusPill` (available/booked/sold, paid/unpaid), `Chip`, `ProductTile` (image hero), `Avatar`, `MoneyText`, `AppBottomSheet`, `EmptyState` (with Trudy personality), skeleton loaders.

### Visual language
- Photo-forward: large product images, gallery grids, hero image transition on tap — the app should feel like the seller's Instagram.
- Boutique-premium palette: elevate the current purple toward a deep plum + a warm accent (gold/rose) that reads ethnic/festive rather than corporate-SaaS. Exact palette compared visually before locking.
- Thumb-friendly one-hand use, haptics, smooth transitions, delightful success moments.

### Consistency pass
Replace scattered hardcoded styles with the theme as each screen is rebuilt. Exact palette, product-tile, and invoice layouts to be finalized with visual mockups (browser companion) at build time.

---

## 8. Security (production-grade)

- **Auth:** Supabase phone OTP (existing). Session persisted in `flutter_secure_storage`. Gate all data screens behind an authenticated session.
- **Row Level Security:** enabled on **every** table, deny-by-default; policies restrict rows to `user_id = auth.uid()`. No table ships without RLS. Verified via Supabase security advisors after each migration.
- **Storage policies:** private buckets; users can only access their own objects. Display via short-lived signed URLs, never public URLs. Payment proofs and product photos both private.
- **Secrets discipline:** no secrets committed. Supabase URL + anon key supplied via `--dart-define` at build (env file holds dev defaults only). `service_role` key never in the app; any privileged operation goes through an Edge Function.
- **Input validation:** validate phone, amounts, quantities, GSTIN format; rely on Supabase parameterized queries (no string-built SQL). Guard against negative/overflow amounts in money math.
- **PII handling:** customer phone/address are PII — collect the minimum, keep private via RLS, and make it deletable/exportable (see store requirements).
- **Payments:** UPI deep-link only — no card data, no gateway, minimal PCI scope. Proof screenshots stored privately.
- **Transport:** HTTPS only (Supabase default). Optional certificate pinning considered.
- **Least privilege:** narrow RLS policies; no broad `using (true)` policies.

---

## 9. Store readiness (Google Play + Apple App Store)

- **Privacy policy + Terms:** screens already exist; host canonical URLs and link them.
- **Data disclosures:** complete Google Play **Data Safety** form and Apple **Privacy Nutrition** labels — declare collected data (name, phone, address, photos) and usage.
- **Permissions with rationale, requested only when needed:** Camera (catalog photos), Photo Library, Microphone (voice intake), Notifications. iOS `Info.plist` usage strings + Android manifest declarations, each with a clear purpose string.
- **Account deletion (in-app):** required by Google Play — Profile → Delete account wipes all user data (and a data-export option to satisfy privacy norms).
- **App signing:** Google Play App Signing; iOS distribution certificate + provisioning profiles.
- **Versioning:** semantic version + build number discipline.
- **Observability:** integrate crash/error reporting (Sentry or Firebase Crashlytics) for production monitoring.
- **Resilience:** graceful offline/error states; retries; no data loss on flaky networks.
- **Performance:** compress images on upload (photos are heavy), lazy-load and paginate lists.
- **Ratings:** complete content/age-rating questionnaires. No cross-app tracking → iOS ATT not required.
- Icons and native splash are already configured.

---

## 10. Testing and observability

The app currently has effectively no tests; production-grade requires coverage of the risky parts.

- **Unit tests:** money math (line totals, subtotal, GST split, dues), invoice numbering, UPI link construction, availability/booking transitions.
- **Widget/flow tests:** enquiry → order → payment → receipt happy path; catalog add.
- **RLS tests:** verify a user cannot read another user's rows.
- **Observability:** crash reporting wired from first production build; basic funnel/event logging (privacy-respecting) to see where sellers drop off.

---

## 11. Build stages

The slice is large but coherent; the implementation plan will stage it so each stage is independently shippable and reviewable. DB changes are applied as reviewable Supabase migrations via MCP (with a read-only check first, and advisors run after).

0. **Design system** — theme tokens + component kit; adopt incrementally.
1. **Data model + security foundation** — tables, RLS (deny-by-default), storage buckets, business-profile setup (name, UPI, optional GSTIN).
2. **Image-first catalog** — photo upload/compress, price, unique/stocked toggle, availability states.
3. **Customers** — entity, phone dedupe, shipping address; refactor enquiries to `customer_id`; rename Leads → Enquiries.
4. **Enquiry → Order** — booking (reserve unique piece), orders table, status + shipping/tracking share.
5. **Payments** — partial/advance + UPI QR/link + proof screenshots; dues roll-up.
6. **Receipt/Invoice** — client-side PDF, GST optional, UPI QR embedded, WhatsApp share.
7. **Dashboard + Trudy** — sales/dues/conversion dashboard, daily brief, re-market past buyers.
8. **Store hardening** — account deletion/export, crash reporting, data-safety forms, permission rationale strings, release signing.

---

## 12. Future phases (out of scope here)

- **Smart Trudy:** LLM-based DM parsing and richer message drafting.
- **True WhatsApp automation:** WhatsApp Cloud API for automated sends.
- **Shareable catalog / web storefront** link.
- **Insights+:** cohort/repeat-buyer analytics, festival campaigns.
- **Payment gateway / payment links** beyond UPI deep-link.

---

## 13. Assumptions

- Single-seller accounts (no staff/multi-user) for v1.
- INR only; India-centric (UPI, GST, 10-digit phones).
- GST v1 assumes intra-state (CGST + SGST split); IGST handled in a later iteration.
- Existing phone-OTP auth and the follow-up notification engine are retained and built upon.
- Supabase project access is granted for direct migration application.
