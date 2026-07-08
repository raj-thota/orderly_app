# Closr — Orders Completion (Stage 4) Design Spec

Extends the parent pipeline spec (`2026-07-04-closr-social-seller-pipeline-design.md`, §Orders). Builds the fulfillment half of the pipeline: a typed Orders feature on the real `orders`/`order_items` schema, the pending→packed→shipped→delivered lifecycle with courier/tracking and WhatsApp share, and a redesigned Orders list + detail on the design system. Supersedes the legacy map-based Orders screen.

## 1. Problem

- The current `OrdersScreen` is legacy: it reads `ordersControllerProvider` (a `List<Map<String,dynamic>>` shim) keyed on the old `order_status` values (`pending`/`processing`/`completed`) that do not match the real schema (`pending`/`packed`/`shipped`/`delivered`), uses hardcoded colors off the design system, and computes a naive "Total Revenue" by summing every order including unpaid ones.
- Order mutations run through the `LeadsController` compatibility shim (`updateOrderStatus`, `updateOrderItems`, `markDone`) written for the retired flow.
- Unique-piece booking (Slice A) is half-finished: converting an enquiry reserves a piece as `booked`, but nothing ever moves it to `sold`.
- `orders.order_number` exists but is never populated, so orders have no human-friendly reference.

## 2. Goals

1. A typed Orders feature (`data`/`controller`/`presentation`/`widgets`) following the catalog and enquiries patterns, replacing the legacy shim usage on the Orders screen.
2. The full order lifecycle: pending → packed → shipped → delivered, with courier + tracking captured at ship and a one-tap WhatsApp tracking share.
3. Delivery closes the unique-piece booking (`piece_status` → `sold`), atomically.
4. Sequential, human-friendly order numbers assigned at creation.
5. A redesigned Orders list (filter chips + design-system cards, default "Active") and a new order detail screen with a status stepper.

### Non-goals (this stage)

- Payments (mark paid/partial, UPI QR/link, proofs, dues) — stage 5. `payment_status` is shown read-only here.
- Invoice/receipt PDF — stage 6.
- Dashboard revenue/analytics — stage 7 (the Orders screen carries no revenue card).
- Editing order line items after creation, order cancellation/refunds, and un-delivering — out of scope.

## 3. Architecture

New `lib/features/orders/` mirroring the enquiries feature:

- `data/order.dart` — `Order` and `OrderItem` typed models with tolerant `fromMap` (flattens the `customers` join to `customerName`/`customerPhone`; parses `order_items` into `List<OrderItem>`; numeric fields via `double.tryParse`/`int.tryParse`).
- `data/orders_service.dart` — thin Supabase client: `fetchOrders()` (with joins, ordered by `created_at desc`), `fetchById(id)`, `updateOrder(id, changes)` (RLS-scoped by `user_id`), and `markDelivered(id)` calling the `mark_order_delivered` RPC.
- `controller/orders_provider.dart` — `ordersServiceProvider` (auth-scoped like `productsServiceProvider`) and `ordersControllerProvider` (`StateNotifierProvider<OrdersController, AsyncValue<List<Order>>>`), with `load()`, `advanceTo(order, status, {courier, trackingNo})`, and `markDelivered(order)`. Auth-scoped so state resets on user change.
- `presentation/orders_screen.dart` — rebuilt list.
- `presentation/order_detail_screen.dart` — new detail.
- `widgets/order_card.dart` — one card.

The legacy order path is retired: `OrdersScreen` stops using `ordersControllerProvider` (the legacy `List<Map>` provider in `features/orders/controller/orders_provider.dart` is replaced by the typed one), and the dead order-mutation methods on `LeadsController` (`updateOrderStatus`, `updateOrderItems`, `markDone`) and the legacy `OrdersList` widget are removed. The enquiry-side legacy shim (`EnquiriesService.fetchLegacyMaps`, used by Dashboard and notifications) is left intact — Dashboard is stage 7.

## 4. Data model

No new columns. Uses existing `orders` (`order_number`, `status` check `pending|packed|shipped|delivered`, `courier`, `tracking_no`, `shipped_at`, `delivered_at`, `payment_status`, `subtotal`/`tax_total`/`grand_total`, `notes`) and `order_items` (`name`, `image_url`, `unit_price`, `gst_rate`, `qty`, `line_total`, `product_id`) from `0001_core_schema.sql`. RLS already covers both.

**Migration `0010_order_lifecycle.sql`:**

1. Update `create_order_with_items` (currently in `0006`) to assign `order_number` at insert:
   ```sql
   insert into orders (user_id, customer_id, lead_id, notes, order_number)
   values (
     auth.uid(), p_customer_id, p_lead_id, p_notes,
     (select coalesce(max(order_number), 0) + 1 from orders where user_id = auth.uid())
   )
   ```
   All other logic (ownership checks, unique-piece booking guard, item insert, totals, lead→won) is preserved verbatim.
2. Add `mark_order_delivered(p_order_id uuid) returns void`, `security invoker`, `set search_path = public`:
   - Verify the order belongs to `auth.uid()` (else `raise exception 'order_not_found'`).
   - `update orders set status = 'delivered', delivered_at = now() where id = p_order_id and user_id = auth.uid();`
   - Flip booked unique pieces to sold:
     ```sql
     update products set piece_status = 'sold'
     where user_id = auth.uid() and is_unique and piece_status = 'booked'
       and id in (select product_id from order_items
                  where order_id = p_order_id and product_id is not null);
     ```
   - `revoke all ... from public, anon; grant execute ... to authenticated;`

## 5. Status lifecycle

Linear, forward-only: **pending → packed → shipped → delivered**.

- **pending → packed:** `updateOrder(id, {'status': 'packed'})`.
- **packed → shipped:** requires `courier` and `tracking_no`; the detail screen shows a dialog capturing both, then `updateOrder(id, {'status': 'shipped', 'courier': c, 'tracking_no': t, 'shipped_at': now})`. Shipping is blocked if either field is empty.
- **shipped → delivered:** `markDelivered(id)` → the `mark_order_delivered` RPC (sets `delivered_at`, marks unique pieces sold).
- The detail screen's primary button reads "Mark as packed / shipped / delivered" per current status; delivered shows no advance button (terminal).

## 6. Share tracking

On a shipped (or delivered) order with a customer phone, a "Share tracking" action composes a plain-text WhatsApp message — `"Hi <name>, your order #<order_number> has shipped via <courier>. Tracking: <tracking_no>."` — and opens `https://wa.me/91<phone>?text=<url-encoded>` via `launchUrl(externalApplication)`, reusing the valid-10-digit-phone guard from the quotation slice (fall back to `wa.me/` with no number when the phone is not a valid mobile). The message is URL-encoded. No auto-send; the user taps to share.

## 7. UI/UX

**OrdersScreen** (design system: `AppColors`, `AppSpacing`, `AppCard`, `StatusPill`, `Money.inr`):
- Lean header: "Orders" title (no revenue card).
- A horizontally scrollable filter-chip row: `Active` (default; = pending + packed + shipped), `Pending`, `Packed`, `Shipped`, `Delivered`, each with a count.
- `AsyncValue.when` (loading spinner / error + Retry / data). `RefreshIndicator` on the list.
- `OrderCard` per order: `#<order_number>`, customer name, `Money.inr(grandTotal)`, item count + status `StatusPill`, a payment-status pill, and the first item names joined. Tapping opens the detail.
- Empty state: "No orders yet.\nConvert an enquiry to start fulfilling."

**OrderDetailScreen:**
- App bar shows `#<order_number>` and the customer name.
- Customer row with WhatsApp + Call (reusing the enquiry detail contact pattern).
- A compact status stepper (pending → packed → shipped → delivered) with the current step highlighted, plus a primary `AppPrimaryButton` "Mark as \<next>" (busy-guarded; hidden when delivered).
- Items: each row shows the thumbnail (or an icon), name, `qty × unit_price`, and line total; then subtotal / grand total.
- Shipping block: courier + tracking when set; the "Share tracking" button on shipped/delivered orders.
- A read-only payment-status pill and any order notes.

**StatusPill:** extend `StatusPillStyle.forStatus` to map `packed`/`shipped`/`delivered` (and keep `pending`) to sensible colors (e.g. pending → neutral, packed → info, shipped → warning/accent, delivered → success).

## 8. Error handling

- Advancing to shipped with a missing courier or tracking number → the capture dialog blocks confirmation until both are filled.
- `updateOrder`/`markDelivered` failure → a retry snackbar; the list reloads on success.
- Delivered is terminal (no un-deliver control this stage).
- If `payment_status` or totals are absent/legacy, the models default them safely (0 / 'unpaid').

## 9. Testing

- **Unit (models):** `Order.fromMap` flattens the customer join, parses items and totals, tolerates missing fields; `OrderItem.fromMap` computes/reads `lineTotal`.
- **Controller:** `load` exposes orders; `advanceTo` sends the right change map per transition (packed; shipped with courier/tracking/shipped_at); `markDelivered` calls the RPC path; filter logic (`Active` excludes delivered; each status chip filters correctly); state resets when the signed-in user changes.
- **Service/DB:** `mark_order_delivered` verified on the remote project — delivering an order with a booked unique piece flips it to `sold`; `create_order_with_items` assigns the next `order_number`; both functions confirmed `prosecdef` correct and advisors unchanged from baseline.
- **Widget:** OrdersScreen renders chips with counts and filters the cards; empty state; OrderDetail shows the stepper, the correct "Mark as \<next>" label, blocks shipping without courier/tracking, and shows "Share tracking" only on shipped/delivered.

## 10. Security

- RLS on `orders`/`order_items`/`products` already in place; every service query scoped by `user_id`.
- `mark_order_delivered` is `security invoker` (runs under the caller's RLS) with a pinned `search_path`, verifies order ownership, and only ever touches `auth.uid()` rows; execute revoked from `public`/`anon`, granted to `authenticated`.
- The WhatsApp tracking message is URL-encoded; the phone is digits-only and validated before building the link. No model/user input triggers a privileged action without the user's explicit tap.

## 11. Definition of done

`flutter analyze` clean (baseline exceptions only), all tests green, code-reviewed, migration `0010` applied and advisors unchanged, legacy Orders screen + dead shim order methods removed, device smoke of the lifecycle (convert enquiry → order gets a number → pack → ship with courier/tracking → share tracking on WhatsApp → deliver → unique piece shows Sold).
