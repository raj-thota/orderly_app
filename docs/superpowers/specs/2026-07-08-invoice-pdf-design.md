# Closr — Invoice PDF (Stage 6) Design Spec

Extends the parent pipeline spec (`2026-07-04-closr-social-seller-pipeline-design.md`, §Receipt/Invoice) and builds on Stage 4 (Orders) + Stage 5 (Payments). Adds on-demand, client-side invoice PDFs generated from order data — no storage, regenerable — with three predefined templates the seller can switch between, GST shown only when the business has a GSTIN, an embedded UPI QR, and share via the OS sheet (WhatsApp). A new Invoices tab lists everything invoiced.

## 1. Problem

- Orders can be fulfilled and paid, but the seller has no way to hand the customer a receipt/invoice.
- `orders.invoice_number` and `business_profile.invoice_prefix`/`next_invoice_number` exist since `0001` but nothing assigns or formats a number.
- Sellers want a choice of invoice looks, not one hardcoded layout.

## 2. Goals

1. A typed Invoices feature (`data`/`pdf`/`controller`/`presentation`) that turns an `Order` + `BusinessProfile` into a shareable PDF.
2. Three predefined templates — **Classic** (default), **Minimal**, **Boutique** — behind a registry, switchable per invoice; the default is stored on the business profile.
3. Sequential, human-friendly invoice numbers assigned once per order (atomic increment on `business_profile`), stored on the order.
4. GST optional: CGST + SGST lines (intra-state 50/50) shown **only** when the business has a GSTIN; otherwise a clean receipt. Prices treated as tax-inclusive so the invoice total equals the order's `grand_total`.
5. Embedded UPI QR (reusing `buildUpiUri`), paid/dues shown, and share via the OS share sheet (WhatsApp).
6. An Invoices tab listing invoiced orders, each re-openable to preview/re-share.

### Non-goals (this stage)

- Storing PDFs anywhere — generated on demand, regenerable from order data.
- Logo image embedding — templates show the business name as text; logo is later polish.
- IGST / inter-state GST — v1 assumes intra-state (CGST + SGST).
- Editing a generated invoice, credit notes, custom user-designed templates.
- Changing an order's `grand_total` to carry tax — GST is extracted (tax-inclusive) for display only.

## 3. Architecture

New `lib/features/invoices/`:

- `data/invoice_data.dart` — `InvoiceData` (pure value type) + `InvoiceData.fromOrder(Order, BusinessProfile)`. Holds business (name, address, phone, gstin, upiId, upiName), customer (name, phone), `invoiceNumber`, `date`, a `List<InvoiceLine>` (name, qty, unitPrice, gstRate, lineTotal), `subtotal`, GST breakdown (`taxable`, `cgst`, `sgst`, `hasGst`), `grandTotal`, `paid`, `dues`, and `upiUri`. GST is computed here (tax-inclusive extraction, §5).
- `data/invoice_service.dart` — `assignInvoiceNumber(orderId)` calling the `assign_invoice_number` RPC (returns the formatted number). Auth-scoped construction like `ordersServiceProvider`.
- `pdf/classic.dart`, `pdf/minimal.dart`, `pdf/boutique.dart` — each exposes a **synchronous** builder `Uint8List <name>Pdf(InvoiceData data, Uint8List? qrImage)`, pure, no I/O (the QR is passed in pre-rendered).
- `pdf/invoice_pdf.dart` — an `InvoiceTemplate` enum (`classic`, `minimal`, `boutique`) with parse/label helpers and `Future<Uint8List> buildInvoicePdf(InvoiceData data, InvoiceTemplate template)`. It first renders the UPI QR to PNG bytes (via `qr_flutter`'s `QrPainter(...).toImageData(size)`, async — hence the `Future`) when `data.upiUri` is set, then dispatches to the matching synchronous template builder. `PdfPreview`'s `build` callback accepts a `FutureOr<Uint8List>`, so the async return integrates directly.
- `controller/invoice_provider.dart` — `invoiceServiceProvider` (auth-scoped) and `InvoiceController extends StateNotifier<AsyncValue<void>>` with `prepare(Order order) → Future<String?>`: assigns the number once (idempotent RPC), reloads orders so the order carries `invoiceNumber`, returns the number (or null on failure).
- `presentation/invoice_share_screen.dart` — pushed with an `Order`. On open it `prepare`s the invoice; shows a `Classic / Minimal / Boutique` chip row (preselected to the profile default) and a `printing` `PdfPreview` of the selected template; `PdfPreview`'s built-in actions share/print (OS sheet → WhatsApp). Switching a chip rebuilds the preview.
- `presentation/invoices_screen.dart` — the Invoices tab: watches `ordersControllerProvider`, filters `invoiceNumber != null`, lists newest first; each card taps to `InvoiceShareScreen`.

Reuses: `Order`/`ordersControllerProvider` (Stage 4), `buildUpiUri` (Stage 5), `businessProfileProvider`, `Money.inr`, design tokens, `StatusPill`, `AppCard`.

Modified: `lib/features/orders/data/order.dart` (add `invoiceNumber` from `invoice_number`), `lib/features/orders/presentation/order_detail_screen.dart` (a "Share invoice" action → `InvoiceShareScreen`), `lib/features/business/**` setup screen (an "Invoice template" dropdown bound to `invoice_template`), `lib/main.dart` + `lib/shared/widgets/app_bottom_nav.dart` (5th tab), `pubspec.yaml` (`pdf`, `printing`).

## 4. Data model

**Migration `0014_invoice_support.sql`:**

1. `alter table business_profile add column invoice_template text not null default 'classic' check (invoice_template in ('classic','minimal','boutique'));`
2. `assign_invoice_number(p_order_id uuid) returns text`, `security invoker`, `set search_path = public`:
   - Verify the order belongs to `auth.uid()` (else `raise exception 'order_not_found'`).
   - If the order already has a non-null `invoice_number`, return it unchanged (idempotent — never burns a number twice).
   - Else read the caller's `business_profile` row `for update` (lock), format `v_number := invoice_prefix || lpad(next_invoice_number::text, 4, '0')`, set it on the order, `update business_profile set next_invoice_number = next_invoice_number + 1`, and return `v_number`.
   - `revoke all ... from public, anon; grant execute ... to authenticated;`

`Order` gains `invoiceNumber` (String?, from `invoice_number`). No change to `orders`/`order_items`/`payments` columns; `orders_service` already selects `*`.

## 5. GST (tax-inclusive extraction)

Computed in `InvoiceData.fromOrder`, only when `business.gstin` is a non-empty string (`hasGst`):

- Per line with a `gstRate r > 0`, the `lineTotal` is treated as GST-inclusive: `taxable = lineTotal / (1 + r/100)`, `lineTax = lineTotal − taxable`.
- `taxable` sums the per-line taxable amounts; `cgst = sgst = totalTax / 2`.
- `grandTotal` stays `order.grandTotal` (== sum of line totals), so what is billed equals what was quoted/collected — no reconciliation drift.
- Lines with `gstRate == 0` (or null) contribute their full amount to `taxable` and no tax.
- When `hasGst` is false, no GST fields are shown; `subtotal == grandTotal`.

All money rounded to paise for display.

## 6. Invoice numbering

- Assigned lazily the first time `InvoiceShareScreen` opens for an order (via `InvoiceController.prepare` → `assign_invoice_number`). Idempotent: reopening returns the same number; a number is only consumed when an order is first invoiced.
- Format: `<invoice_prefix><4-digit zero-padded number>`, e.g. `INV-0042`. Stored on `orders.invoice_number`.

## 7. UI/UX

**InvoiceShareScreen** (design system):
- App bar: `Invoice #<number>` (or `Invoice` while preparing).
- A horizontally scrollable chip row: `Classic` / `Minimal` / `Boutique`, preselected to `business_profile.invoice_template`.
- A `PdfPreview` (from `printing`) rendering `buildInvoicePdf(data, selected)`; its built-in toolbar provides share (OS sheet → WhatsApp) and print. Switching a chip re-renders.
- While `prepare` runs: a spinner; on failure: an error + Retry.

**Templates** (all show: business name/address/phone, GSTIN when set, `Invoice #<number>` + date, `Bill to` customer, an items table, subtotal, CGST/SGST when `hasGst`, total, paid + dues, and the UPI QR + `upi_id`):
- **Classic** — bordered header + bordered items table + boxed totals; formal tax-invoice look.
- **Minimal** — borderless, generous whitespace, thin rules, right-aligned totals, small QR.
- **Boutique** — brand-colour header band, centered business name, styled totals, accent colour.

**Invoices tab** (`InvoicesScreen`):
- `AsyncValue.when` over `ordersControllerProvider`, filtered to `invoiceNumber != null`, newest first (`createdAt` desc).
- Each `AppCard`: `#<invoice_number>`, customer name, date, `Money.inr(grandTotal)`, and a `payment_status` `StatusPill`; tap → `InvoiceShareScreen`.
- Empty state: "No invoices yet.\nShare an invoice from an order to see it here."

**OrderDetailScreen** — a "Share invoice" action (e.g. an outlined button under the payment card) → `InvoiceShareScreen`.

**Business setup** — an "Invoice template" dropdown (`Classic`/`Minimal`/`Boutique`) bound to `invoice_template`, saved with the rest of the profile.

**Navigation** — `MainScreen` adds `InvoicesScreen` as tab index 4; `AppBottomNav` gains a 5th item (receipt icon, "Invoices"). The FAB is hidden on the Invoices tab.

## 8. Error handling

- `assign_invoice_number` failure → the share screen shows an error + Retry; no partial state (the RPC is atomic).
- A template that throws while building → the preview surfaces an error rather than crashing the screen (each builder is wrapped).
- No GSTIN → GST lines are simply omitted.
- Missing `upi_id` → the QR/UPI block is omitted from the PDF.
- Sharing is delegated to `printing`; a share cancel is a no-op.

## 9. Security

- `assign_invoice_number` is `security invoker` (runs under the caller's RLS) with a pinned `search_path`, verifies order ownership, and only ever reads/writes `auth.uid()`'s own `orders`/`business_profile` rows; execute revoked from `public`/`anon`, granted to `authenticated`. The `for update` lock on the profile row makes concurrent numbering safe.
- PDFs are generated client-side and never stored; no bucket, no public URL.
- GSTIN and amounts come from owned rows; the UPI URI encodes the seller's own VPA. No untrusted input triggers a privileged action.
- Advisors must be unchanged from baseline (9 WARN + 1 INFO) after `0014` — `assign_invoice_number` is invoker, adding no new finding.

## 10. Testing

- **Unit (`InvoiceData.fromOrder`):** GST-inclusive extraction with a GSTIN (per-line `taxable`/`cgst`/`sgst`, total equals `grandTotal`); no GST when GSTIN absent; paid/dues from the order; number/date passthrough; lines with `gstRate == 0` contribute no tax.
- **PDF smoke (`buildInvoicePdf`):** for each of the three templates × (GST / no-GST / dues-outstanding / fully-paid) inputs, `await buildInvoicePdf(...)` returns non-empty bytes and does not throw (with and without a UPI URI, i.e. QR present/absent).
- **DB:** `assign_invoice_number` verified on the remote project — invoker + pinned `search_path`, idempotent (second call returns the same number, `next_invoice_number` incremented once), advisors unchanged from baseline.
- **Widget:** `InvoiceShareScreen` renders three template chips with the profile default preselected and switches selection on tap; `InvoicesScreen` lists only orders with an `invoiceNumber`, shows the empty state otherwise.

## 11. Definition of done

`flutter analyze` clean (baseline exceptions only), all tests green, code-reviewed, migration `0014` applied and advisors unchanged, `pdf`/`printing` added, and a device smoke: open a delivered/paid order → Share invoice → number `INV-0001` assigned → switch Classic/Minimal/Boutique in the preview → GST lines appear only when a GSTIN is set → share opens the OS sheet to WhatsApp with the PDF → the order now appears under the Invoices tab → reopening shows the same number.
