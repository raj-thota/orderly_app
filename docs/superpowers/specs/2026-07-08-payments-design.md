# Closr — Payments (Stage 5) Design Spec

Extends the parent pipeline spec (`2026-07-04-closr-social-seller-pipeline-design.md`, §Payments) and builds on Stage 4 (Orders lifecycle). Adds a typed Payments feature: recording manual payments (amount + method), deriving `orders.payment_status` and per-order dues from the sum of payments, and a UPI collect flow (in-app QR + a WhatsApp share link) that lets a customer pay the seller's UPI VPA. `orders.payment_status` stops being read-only.

## 1. Problem

- `orders.payment_status` (`unpaid`/`partial`/`paid`) and the `payments` table exist since `0001` but nothing writes to them — the Orders detail shows a read-only `unpaid` pill and there is no way to record money received.
- Sellers take partial advances and balances over WhatsApp; the app must track paid vs. dues per order.
- The seller has a UPI VPA (`business_profile.upi_id`/`upi_name`) but no way to present a scannable QR or send a pay link to the customer.

## 2. Goals

1. A typed Payments feature (`data`/`controller`/`widgets`) following the orders/enquiries patterns.
2. Record a payment (amount + method `upi`/`cash`/`other`) against an order; support multiple payments (advance + balance).
3. Derive `orders.payment_status` and per-order dues from `sum(payments.amount)` vs `grand_total`, updated atomically when a payment is recorded.
4. UPI collect: an in-app scannable QR encoding the seller's VPA + the outstanding amount, plus a one-tap "Send payment link on WhatsApp".
5. Surface paid / dues on the Order detail with the (now live) `payment_status` pill.

### Non-goals (this stage)

- Payment proof screenshots (`payments.proof_image_url` stays null) — a later slice.
- Editing or deleting recorded payments; refunds/reversals.
- Global dues roll-up across all orders (a "total outstanding" figure) — Stage 7 dashboard.
- Payment gateway / card processing — UPI deep-link only, per the parent spec (keeps PCI scope out).
- Auto-reconciliation of UPI payments — recording stays manual; the QR/link only helps the customer pay.

## 3. Architecture

New `lib/features/payments/`:

- `data/payment.dart` — `Payment` typed model with tolerant `fromMap` (`amount` via `double.tryParse`, `method`, `paidAt` via `DateTime.tryParse`).
- `data/payments_service.dart` — thin Supabase client: `recordPayment(orderId, amount, method)` calling the `record_payment` RPC. Auth-scoped construction like `ordersServiceProvider`.
- `controller/payments_provider.dart` — `paymentsServiceProvider` (auth-scoped) and a `PaymentsController extends StateNotifier<AsyncValue<void>>` holding the service and a `Ref`. Its `recordPayment(orderId, amount, method)` calls the service, then `ref.read(ordersControllerProvider.notifier).load()` so the detail reflects the new dues/status. Kept separate from Stage 4's `OrdersController` so that controller and its tests stay untouched.
- `widgets/record_payment_sheet.dart` — a `StatefulWidget` bottom sheet (owns its `TextEditingController`, disposed in `dispose`) capturing amount + method; validates amount `> 0`.
- `widgets/upi_collect_sheet.dart` — a bottom sheet rendering the UPI QR (`qr_flutter`) + VPA + a "Send payment link on WhatsApp" button.
- `data/upi.dart` — a pure `buildUpiUri({vpa, name, amount, note})` helper returning the `upi://pay?...` string, unit-tested in isolation.

Reuses: `OrdersController`/`ordersControllerProvider` (Stage 4) for reloads, `businessProfileProvider` for the VPA, `Money.inr`, design tokens, `AppCard`, `AppPrimaryButton`, `StatusPill`, the validated-mobile regex `^[6-9]\d{9}$` and `_openUri` pattern from `order_detail_screen.dart`.

**Recording flow:** the payment is inserted and `orders.payment_status` recomputed inside one RPC (atomic), mirroring `create_order_with_items`/`mark_order_delivered`. The controller calls the service, then `ref.read(ordersControllerProvider.notifier).load()` so the Order (with joined payments) refreshes.

## 4. Data model

No new columns. Uses existing `payments` (`order_id`, `user_id`, `amount`, `method` check `upi|cash|other`, `proof_image_url` nullable, `paid_at`) and `orders.payment_status` (check `unpaid|partial|paid`) from `0001`. RLS on `payments` is already in place (`0002`).

- `Order` (Stage 4 model) gains `List<Payment> payments` parsed from a `payments(*)` join, plus computed getters `paidTotal` (`sum of payment amounts`) and `dues` (`max(grandTotal - paidTotal, 0)`).
- `OrdersService._selectWithJoins` becomes `'*, customers(name, phone), order_items(*), payments(*)'`.

**Migration `0012_record_payment.sql`:**

`record_payment(p_order_id uuid, p_amount numeric, p_method text)` `returns void`, `security invoker`, `set search_path = public`:
1. `if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;`
2. `if p_method is null or p_method not in ('upi','cash','other') then raise exception 'invalid_method'; end if;`
3. Verify the order belongs to `auth.uid()` (else `raise exception 'order_not_found'`).
4. `insert into payments (user_id, order_id, amount, method) values (auth.uid(), p_order_id, p_amount, p_method);`
5. Recompute status:
   ```sql
   update orders o set payment_status = case
     when coalesce(paid.total, 0) <= 0 then 'unpaid'
     when coalesce(paid.total, 0) >= o.grand_total then 'paid'
     else 'partial'
   end
   from (select coalesce(sum(amount), 0) as total
         from payments where order_id = p_order_id) paid
   where o.id = p_order_id and o.user_id = auth.uid();
   ```
6. `revoke all on function public.record_payment(uuid, numeric, text) from public, anon; grant execute ... to authenticated;`

## 5. UPI collect

`buildUpiUri` composes `upi://pay?pa=<upi_id>&pn=<url-encoded upi_name>&am=<dues, 2dp>&cu=INR&tn=<url-encoded note>` where the note is `Order #<order_number>` (or `Order` when no number). The QR sheet renders it with `QrImageView` (from `qr_flutter`), shows `upi_id (upi_name)` beneath, and a "Send payment link on WhatsApp" button that opens `wa.me/91<phone>?text=<encoded message>` — the message being a short line plus the `upi://` string and amount. The bare `wa.me/` fallback is used when the customer phone is not a valid 10-digit mobile (reusing the Stage 4 guard). Amount comes from the order's `dues`.

The "Collect via UPI" entry point (and this sheet) is shown only when `dues > 0` **and** `business_profile.upi_id` is non-empty; otherwise the button is hidden so no broken/empty QR can render.

## 6. UI/UX

**OrderDetailScreen** — a new payment `AppCard` between the items card and the lifecycle button:
- Rows: `Total <grand_total>`, `Paid <paidTotal>`, `Dues <dues>` (dues emphasized), and the existing `payment_status` `StatusPill`.
- When `dues > 0`: a "Record payment" button (opens `record_payment_sheet`) and, when `upi_id` is set, a "Collect via UPI" button (opens `upi_collect_sheet`).
- When `dues <= 0`: no action buttons (fully paid); the pill reads `Paid`.

**record_payment_sheet** — amount `TextField` (numeric), a method segmented control / choice row (`UPI`/`Cash`/`Other`, default `UPI`), and a busy-guarded "Save" `AppPrimaryButton`. Save is blocked until amount parses `> 0`. On success the sheet closes and the detail reloads.

**upi_collect_sheet** — title `Collect ₹<dues> via UPI`, the QR, `upi_id (upi_name)`, and the WhatsApp share button.

Both sheets use `AppColors`/`AppSpacing`; amounts via `Money.inr`.

## 7. Error handling

- Record sheet blocks empty / non-numeric / `≤ 0` amount before enabling Save.
- `record_payment` RPC failure → a retry snackbar; the order reloads on success. The RPC's own `invalid_amount`/`invalid_method`/`order_not_found` are surfaced as the generic retry snackbar (they shouldn't occur from the validated UI, but the RPC is the real boundary).
- Overpayment (`paidTotal > grand_total`) is allowed → status `paid`, `dues` shows `0` (floored).
- Missing `upi_id` → the UPI button and sheet are not shown.
- `launchUrl` is wrapped (reused `_openUri`) so a thrown `PlatformException` surfaces the "Could not open the app" snackbar rather than an unhandled async error.

## 8. Security

- RLS on `payments`/`orders` already in place; the service never trusts a client-supplied `user_id`.
- `record_payment` is `security invoker` (runs under the caller's RLS) with a pinned `search_path`, validates amount and method, verifies order ownership, inserts only for `auth.uid()`, and recomputes only the caller's order; execute revoked from `public`/`anon`, granted to `authenticated`.
- The UPI URI encodes the seller's own VPA and a numeric amount; the WhatsApp message is URL-encoded and the phone validated before building the link. No model/user input triggers a privileged action without the seller's explicit tap.
- Advisors must be unchanged from the baseline (9 WARN + 1 INFO) after `0012` — `record_payment` is invoker, adding no new finding.

## 9. Definition of done

`flutter analyze` clean (baseline exceptions only), all tests green, code-reviewed, migration `0012` applied and advisors unchanged, `qr_flutter` added to `pubspec.yaml`, and a device smoke: open an order with dues → Record payment (partial) → pill flips to `Partial`, dues drop → Collect via UPI shows a scannable QR for the balance → Send link opens WhatsApp prefilled → Record the balance → pill reads `Paid`, dues `0`, buttons gone.
