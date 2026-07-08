# Stage 4 — Orders Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the legacy map-based Orders screen with a typed Orders feature on the real `orders`/`order_items` schema — the pending→packed→shipped→delivered lifecycle with courier/tracking, WhatsApp tracking share, sequential order numbers, and delivery that closes the unique-piece booking — plus a redesigned list and detail on the design system.

**Architecture:** A new `lib/features/orders/` mirrors the enquiries/catalog feature layering: typed `Order`/`OrderItem` models, a thin `OrdersService` Supabase client, an auth-scoped `OrdersController` (`StateNotifier<AsyncValue<List<Order>>>`), and rebuilt `presentation`/`widgets`. Two DB changes (migration 0010): `create_order_with_items` assigns the next per-user `order_number`, and a new `mark_order_delivered` RPC sets delivered + flips booked unique pieces to sold. The legacy `Provider<List<Map>>` orders path and the dead `LeadsController` order-mutation methods are removed.

**Tech Stack:** Flutter/Dart, Riverpod `StateNotifier` (auth-scoped like `productsControllerProvider`), Supabase (`orders`/`order_items` + two RPCs), existing `StatusPill`/`AppCard`/`Money.inr`/design tokens, `url_launcher` (WhatsApp).

## File Structure

**Database:**
- Create `supabase/migrations/0010_order_lifecycle.sql` — order_number in `create_order_with_items`; new `mark_order_delivered` RPC.

**New (client):**
- `lib/features/orders/data/order.dart` — `Order`, `OrderItem` models.
- `lib/features/orders/data/orders_service.dart` — `OrdersService` (fetch/update/markDelivered).
- `lib/features/orders/controller/orders_provider.dart` — **replaces** the legacy provider file: `ordersServiceProvider` + `ordersControllerProvider` (typed) + a `nextOrderStatus` helper.

**Rewritten (client):**
- `lib/features/orders/presentation/orders_screen.dart` — filter chips + cards.
- `lib/features/orders/presentation/order_detail_screen.dart` — status stepper + lifecycle actions.
- `lib/features/orders/widgets/order_card.dart` — one typed card.

**Removed:**
- `lib/features/orders/widgets/orders_list.dart` (folded into the screen).
- `LeadsController.updateOrderStatus` and `LeadsController.updateOrderItems` (dead after the rewrite; `loadLeads` and `markDone` stay — notifications/dashboard/splash still use them).

**Tests:**
- `test/features/orders/order_test.dart`, `orders_controller_test.dart`, `orders_screen_test.dart`, `order_detail_test.dart`.

---

### Task 1: Migration 0010 — order numbers + delivery RPC

**Files:**
- Create: `supabase/migrations/0010_order_lifecycle.sql`

`create_order_with_items` gains a per-user sequential `order_number` (max+1 inside the RPC transaction; adequate for a solo seller). `mark_order_delivered` sets delivered + flips booked unique pieces to sold, ownership-checked and invoker-scoped.

- [ ] **Step 1: Write the migration**

```sql
-- Assign a per-user sequential order_number at creation, and add an atomic
-- delivery RPC that also closes the unique-piece booking (booked -> sold).

create or replace function public.create_order_with_items(
  p_customer_id uuid,
  p_lead_id uuid,
  p_items jsonb,
  p_book_product_id uuid default null,
  p_notes text default null
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_order_id uuid;
  v_subtotal numeric(12,2) := 0;
  v_item jsonb;
  v_price numeric(12,2);
  v_qty integer;
begin
  if not exists (
    select 1 from customers where id = p_customer_id and user_id = auth.uid()
  ) then
    raise exception 'customer_not_found';
  end if;

  if p_lead_id is not null and not exists (
    select 1 from leads where id = p_lead_id and user_id = auth.uid()
  ) then
    raise exception 'lead_not_found';
  end if;

  if p_book_product_id is not null then
    update products set piece_status = 'booked'
    where id = p_book_product_id
      and user_id = auth.uid()
      and is_unique
      and piece_status = 'available';
    if not found then
      raise exception 'piece_unavailable';
    end if;
  end if;

  insert into orders (user_id, customer_id, lead_id, notes, order_number)
  values (
    auth.uid(), p_customer_id, p_lead_id, p_notes,
    (select coalesce(max(order_number), 0) + 1
       from orders where user_id = auth.uid())
  )
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_qty := greatest(coalesce((v_item->>'qty')::integer, 1), 1);

    insert into order_items
      (user_id, order_id, product_id, name, image_url, unit_price, gst_rate, qty, line_total)
    values (
      auth.uid(),
      v_order_id,
      nullif(v_item->>'product_id', '')::uuid,
      coalesce(nullif(v_item->>'name', ''), 'Item'),
      v_item->>'image_url',
      v_price,
      coalesce((v_item->>'gst_rate')::numeric, 0),
      v_qty,
      v_price * v_qty
    );

    v_subtotal := v_subtotal + v_price * v_qty;
  end loop;

  update orders set subtotal = v_subtotal, grand_total = v_subtotal
  where id = v_order_id;

  if p_lead_id is not null then
    update leads set status = 'won'
    where id = p_lead_id and user_id = auth.uid();
  end if;

  return v_order_id;
end;
$$;

create or replace function public.mark_order_delivered(p_order_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not exists (
    select 1 from orders where id = p_order_id and user_id = auth.uid()
  ) then
    raise exception 'order_not_found';
  end if;

  update orders
  set status = 'delivered', delivered_at = now()
  where id = p_order_id and user_id = auth.uid();

  update products set piece_status = 'sold'
  where user_id = auth.uid()
    and is_unique
    and piece_status = 'booked'
    and id in (
      select product_id from order_items
      where order_id = p_order_id and product_id is not null
    );
end;
$$;

revoke all on function public.mark_order_delivered(uuid) from public, anon;
grant execute on function public.mark_order_delivered(uuid) to authenticated;
```

- [ ] **Step 2: Apply via Supabase MCP**

Use `apply_migration` with `project_id: dgviploqkwyuttcdnddq`, `name: order_lifecycle`, and the SQL above. Expected: `{"success":true}`.

- [ ] **Step 3: Verify both functions are invoker with pinned search_path**

Use `execute_sql` (`project_id: dgviploqkwyuttcdnddq`):

```sql
select proname, prosecdef, proconfig
from pg_proc
where proname in ('create_order_with_items', 'mark_order_delivered')
order by proname;
```

Expected: two rows, both `prosecdef = false`, both `proconfig = {search_path=public}`.

- [ ] **Step 4: Advisors unchanged**

Use `get_advisors` (`type: security`). Expected: the same baseline (9 WARN + 1 INFO). `mark_order_delivered` is invoker, so it adds no `authenticated_security_definer` finding.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0010_order_lifecycle.sql
git commit -m "feat(db): sequential order numbers and delivery RPC that sells booked pieces"
```

---

### Task 2: Order + OrderItem models

**Files:**
- Create: `lib/features/orders/data/order.dart`
- Test: `test/features/orders/order_test.dart`

Typed models with tolerant `fromMap`, mirroring `Enquiry.fromMap` (flatten `customers` join; parse the `order_items` child list; numbers via `tryParse`).

- [ ] **Step 1: Write the failing tests**

Create `test/features/orders/order_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/data/order.dart';

void main() {
  test('fromMap flattens customer, parses items and totals', () {
    final order = Order.fromMap({
      'id': 'o1',
      'order_number': 1042,
      'customer_id': 'c1',
      'customers': {'name': 'Priya', 'phone': '9876543210'},
      'status': 'packed',
      'courier': 'DTDC',
      'tracking_no': 'TRK1',
      'payment_status': 'unpaid',
      'grand_total': '5500',
      'subtotal': '5500',
      'notes': 'gift wrap',
      'order_items': [
        {'name': 'Silk Saree', 'qty': 2, 'unit_price': '2500', 'line_total': '5000'},
        {'name': 'Blouse', 'qty': 1, 'unit_price': '500', 'line_total': '500'},
      ],
    });

    expect(order.orderNumber, 1042);
    expect(order.customerName, 'Priya');
    expect(order.customerPhone, '9876543210');
    expect(order.status, 'packed');
    expect(order.courier, 'DTDC');
    expect(order.trackingNo, 'TRK1');
    expect(order.paymentStatus, 'unpaid');
    expect(order.grandTotal, 5500);
    expect(order.items, hasLength(2));
    expect(order.items.first.name, 'Silk Saree');
    expect(order.items.first.qty, 2);
    expect(order.items.first.lineTotal, 5000);
  });

  test('fromMap tolerates missing joins and fields', () {
    final order = Order.fromMap({'id': 'o2'});
    expect(order.customerName, isNull);
    expect(order.status, 'pending'); // default
    expect(order.paymentStatus, 'unpaid'); // default
    expect(order.grandTotal, 0);
    expect(order.items, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/orders/order_test.dart`
Expected: FAIL — target of URI doesn't exist.

- [ ] **Step 3: Implement the models**

Create `lib/features/orders/data/order.dart`:

```dart
class OrderItem {
  const OrderItem({
    required this.name,
    this.imageUrl,
    this.unitPrice = 0,
    this.qty = 1,
    this.lineTotal = 0,
    this.productId,
  });

  final String name;
  final String? imageUrl;
  final double unitPrice;
  final int qty;
  final double lineTotal;
  final String? productId;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      name: (map['name'] ?? 'Item').toString(),
      imageUrl: map['image_url'] as String?,
      unitPrice: double.tryParse(map['unit_price']?.toString() ?? '') ?? 0,
      qty: int.tryParse(map['qty']?.toString() ?? '') ?? 1,
      lineTotal: double.tryParse(map['line_total']?.toString() ?? '') ?? 0,
      productId: map['product_id']?.toString(),
    );
  }
}

class Order {
  const Order({
    this.id,
    this.orderNumber,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.status = 'pending',
    this.courier,
    this.trackingNo,
    this.shippedAt,
    this.deliveredAt,
    this.paymentStatus = 'unpaid',
    this.subtotal = 0,
    this.grandTotal = 0,
    this.notes,
    this.createdAt,
    this.items = const [],
  });

  final String? id;
  final int? orderNumber;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String status;
  final String? courier;
  final String? trackingNo;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;
  final String paymentStatus;
  final double subtotal;
  final double grandTotal;
  final String? notes;
  final DateTime? createdAt;
  final List<OrderItem> items;

  factory Order.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'];
    final itemsRaw = map['order_items'] as List? ?? const [];
    return Order(
      id: map['id']?.toString(),
      orderNumber: int.tryParse(map['order_number']?.toString() ?? ''),
      customerId: map['customer_id']?.toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      customerPhone: customer is Map ? customer['phone']?.toString() : null,
      status: (map['status'] ?? 'pending').toString(),
      courier: map['courier']?.toString(),
      trackingNo: map['tracking_no']?.toString(),
      shippedAt: DateTime.tryParse(map['shipped_at']?.toString() ?? ''),
      deliveredAt: DateTime.tryParse(map['delivered_at']?.toString() ?? ''),
      paymentStatus: (map['payment_status'] ?? 'unpaid').toString(),
      subtotal: double.tryParse(map['subtotal']?.toString() ?? '') ?? 0,
      grandTotal: double.tryParse(map['grand_total']?.toString() ?? '') ?? 0,
      notes: map['notes']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      items: [
        for (final i in itemsRaw)
          if (i is Map) OrderItem.fromMap(Map<String, dynamic>.from(i)),
      ],
    );
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/orders/order_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/orders/data/order.dart test/features/orders/order_test.dart
git commit -m "feat(orders): typed Order and OrderItem models"
```

---

### Task 3: OrdersService

**Files:**
- Create: `lib/features/orders/data/orders_service.dart`

Thin Supabase client. No unit test (Supabase-bound); it is exercised through the controller's fake in Task 4, matching the enquiries/catalog pattern.

- [ ] **Step 1: Implement the service**

Create `lib/features/orders/data/orders_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order.dart';

const _selectWithJoins = '*, customers(name, phone), order_items(*)';

class OrdersService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<List<Order>> fetchOrders() async {
    final rows = await _client
        .from('orders')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    return rows.map<Order>((r) => Order.fromMap(r)).toList();
  }

  Future<Order?> fetchById(String id) async {
    final row = await _client
        .from('orders')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Order.fromMap(row);
  }

  Future<void> updateOrder(String id, Map<String, dynamic> changes) async {
    await _client
        .from('orders')
        .update(changes)
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Future<void> markDelivered(String id) async {
    await _client.rpc('mark_order_delivered', params: {'p_order_id': id});
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/orders/data/orders_service.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/orders/data/orders_service.dart
git commit -m "feat(orders): OrdersService supabase client"
```

---

### Task 4: OrdersController + provider

**Files:**
- Modify (replace contents): `lib/features/orders/controller/orders_provider.dart`
- Test: `test/features/orders/orders_controller_test.dart`

Auth-scoped provider (mirrors `productsServiceProvider`/`productsControllerProvider`). `advanceTo` maps each transition to the right service call; `markDelivered` uses the RPC path; a top-level `nextOrderStatus` helper and a `filterOrders` helper support the UI.

- [ ] **Step 1: Write the failing tests**

Create `test/features/orders/orders_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';

class FakeOrdersService implements OrdersService {
  FakeOrdersService(List<Order> seed) : _rows = List.of(seed);
  final List<Order> _rows;
  final List<Map<String, dynamic>> updates = [];
  final List<String> delivered = [];

  @override
  Future<List<Order>> fetchOrders() async => List.of(_rows);
  @override
  Future<Order?> fetchById(String id) async =>
      _rows.where((o) => o.id == id).firstOrNull;
  @override
  Future<void> updateOrder(String id, Map<String, dynamic> changes) async {
    updates.add({'id': id, ...changes});
  }
  @override
  Future<void> markDelivered(String id) async => delivered.add(id);
}

void main() {
  test('nextOrderStatus advances linearly and stops at delivered', () {
    expect(nextOrderStatus('pending'), 'packed');
    expect(nextOrderStatus('packed'), 'shipped');
    expect(nextOrderStatus('shipped'), 'delivered');
    expect(nextOrderStatus('delivered'), isNull);
  });

  test('filterOrders Active excludes delivered', () {
    final orders = const [
      Order(id: 'a', status: 'pending'),
      Order(id: 'b', status: 'shipped'),
      Order(id: 'c', status: 'delivered'),
    ];
    expect(filterOrders(orders, OrderFilter.active).map((o) => o.id),
        ['a', 'b']);
    expect(filterOrders(orders, OrderFilter.delivered).map((o) => o.id),
        ['c']);
    expect(filterOrders(orders, OrderFilter.pending).map((o) => o.id), ['a']);
  });

  ProviderContainer makeContainer(FakeOrdersService fake) {
    final container = ProviderContainer(overrides: [
      ordersServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('load exposes orders', () async {
    final fake = FakeOrdersService(const [Order(id: 'o1', status: 'pending')]);
    final c = makeContainer(fake);
    await c.read(ordersControllerProvider.notifier).load();
    expect(c.read(ordersControllerProvider).value, hasLength(1));
  });

  test('advanceTo packed sends a status-only update', () async {
    final fake = FakeOrdersService(const [Order(id: 'o1', status: 'pending')]);
    final c = makeContainer(fake);
    final controller = c.read(ordersControllerProvider.notifier);
    await controller.load();
    await controller.advanceTo(const Order(id: 'o1', status: 'pending'), 'packed');
    expect(fake.updates.single, {'id': 'o1', 'status': 'packed'});
  });

  test('advanceTo shipped records courier, tracking and shipped_at', () async {
    final fake = FakeOrdersService(const [Order(id: 'o1', status: 'packed')]);
    final c = makeContainer(fake);
    final controller = c.read(ordersControllerProvider.notifier);
    await controller.load();
    await controller.advanceTo(const Order(id: 'o1', status: 'packed'), 'shipped',
        courier: 'DTDC', trackingNo: 'TRK1');
    final u = fake.updates.single;
    expect(u['status'], 'shipped');
    expect(u['courier'], 'DTDC');
    expect(u['tracking_no'], 'TRK1');
    expect(u.containsKey('shipped_at'), isTrue);
  });

  test('markDelivered uses the RPC path', () async {
    final fake = FakeOrdersService(const [Order(id: 'o1', status: 'shipped')]);
    final c = makeContainer(fake);
    final controller = c.read(ordersControllerProvider.notifier);
    await controller.load();
    await controller.markDelivered(const Order(id: 'o1', status: 'shipped'));
    expect(fake.delivered, ['o1']);
    expect(fake.updates, isEmpty);
  });

  test('state resets when the signed-in user changes', () async {
    final authEvents = StreamController<String?>();
    final services = <String?, FakeOrdersService>{
      'userA': FakeOrdersService(const [Order(id: 'a1')]),
      'userB': FakeOrdersService(const []),
    };
    final c = ProviderContainer(overrides: [
      authUserIdProvider.overrideWith((ref) => authEvents.stream),
      ordersServiceProvider.overrideWith((ref) {
        final uid = ref.watch(authUserIdProvider).valueOrNull;
        return services[uid] ?? FakeOrdersService(const []);
      }),
    ]);
    addTearDown(c.dispose);
    addTearDown(authEvents.close);

    authEvents.add('userA');
    await c.read(authUserIdProvider.future);
    await c.read(ordersControllerProvider.notifier).load();
    expect(c.read(ordersControllerProvider).value, hasLength(1));

    authEvents.add('userB');
    await Future<void>.delayed(Duration.zero);
    await c.read(ordersControllerProvider.notifier).load();
    expect(c.read(ordersControllerProvider).value, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/orders/orders_controller_test.dart`
Expected: FAIL — the current `orders_provider.dart` exports a `Provider<List<Map>>`, not these symbols.

- [ ] **Step 3: Replace the provider file**

Replace the entire contents of `lib/features/orders/controller/orders_provider.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/providers/auth_providers.dart';

import '../data/order.dart';
import '../data/orders_service.dart';

export 'package:orderly_app/core/providers/auth_providers.dart'
    show authUserIdProvider;

enum OrderFilter { active, pending, packed, shipped, delivered }

/// The next status in the linear lifecycle, or null when terminal.
String? nextOrderStatus(String current) {
  const flow = ['pending', 'packed', 'shipped', 'delivered'];
  final i = flow.indexOf(current);
  if (i < 0 || i >= flow.length - 1) return null;
  return flow[i + 1];
}

/// Filters orders for a chip. `active` = anything not delivered.
List<Order> filterOrders(List<Order> orders, OrderFilter filter) {
  switch (filter) {
    case OrderFilter.active:
      return orders.where((o) => o.status != 'delivered').toList();
    case OrderFilter.pending:
      return orders.where((o) => o.status == 'pending').toList();
    case OrderFilter.packed:
      return orders.where((o) => o.status == 'packed').toList();
    case OrderFilter.shipped:
      return orders.where((o) => o.status == 'shipped').toList();
    case OrderFilter.delivered:
      return orders.where((o) => o.status == 'delivered').toList();
  }
}

final ordersServiceProvider = Provider<OrdersService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return OrdersService();
});

final ordersControllerProvider =
    StateNotifierProvider<OrdersController, AsyncValue<List<Order>>>((ref) {
  return OrdersController(ref.watch(ordersServiceProvider));
});

class OrdersController extends StateNotifier<AsyncValue<List<Order>>> {
  OrdersController(this._service) : super(const AsyncValue.loading());

  final OrdersService _service;

  Future<void> load() async {
    state = await AsyncValue.guard(_service.fetchOrders);
  }

  Future<void> advanceTo(
    Order order,
    String status, {
    String? courier,
    String? trackingNo,
  }) async {
    if (status == 'delivered') {
      await markDelivered(order);
      return;
    }
    final changes = <String, dynamic>{'status': status};
    if (status == 'shipped') {
      changes['courier'] = courier;
      changes['tracking_no'] = trackingNo;
      changes['shipped_at'] = DateTime.now().toIso8601String();
    }
    await _service.updateOrder(order.id!, changes);
    await load();
  }

  Future<void> markDelivered(Order order) async {
    await _service.markDelivered(order.id!);
    await load();
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/orders/orders_controller_test.dart`
Expected: PASS (8 tests). Note: the app will not fully compile yet — the legacy `orders_screen.dart`/`order_detail_screen.dart`/`order_card.dart` still import the old provider symbols; they are rewritten in Tasks 5–6. Do NOT run `flutter analyze` on the whole project until Task 6.

- [ ] **Step 5: Commit**

```bash
git add lib/features/orders/controller/orders_provider.dart test/features/orders/orders_controller_test.dart
git commit -m "feat(orders): auth-scoped OrdersController with lifecycle transitions"
```

---

### Task 5: OrderCard + redesigned OrdersScreen

**Files:**
- Modify (replace contents): `lib/features/orders/widgets/order_card.dart`
- Modify (replace contents): `lib/features/orders/presentation/orders_screen.dart`
- Test: `test/features/orders/orders_screen_test.dart`

The card is a design-system `AppCard` summarising one order; the screen is a lean header + scrollable filter chips (default `active`) over an `AsyncValue.when` list.

- [ ] **Step 1: Write the OrderCard**

Replace the entire contents of `lib/features/orders/widgets/order_card.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';
import 'package:orderly_app/shared/widgets/status_pill.dart';

import '../data/order.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final itemNames = order.items.map((i) => i.name).join(', ');
    // AppCard has no onTap; wrap it in an InkWell for the tap affordance.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AppCard(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                order.orderNumber != null ? '#${order.orderNumber}' : 'Order',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  order.customerName ?? 'Customer',
                  style: const TextStyle(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                Money.inr(order.grandTotal),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text('${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(width: AppSpacing.sm),
              StatusPill(status: order.status),
              const SizedBox(width: AppSpacing.sm),
              StatusPill(status: order.paymentStatus),
            ],
          ),
          if (itemNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(itemNames,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ],
        ),
      ),
    );
  }
}
```

Note: `AppCard` has no `onTap` (verified: `const AppCard({super.key, required this.child, this.padding})`), so the card is wrapped in an `InkWell` for the tap affordance. `dart format` will re-indent the nested block on save.

- [ ] **Step 2: Write the OrdersScreen**

Replace the entire contents of `lib/features/orders/presentation/orders_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../controller/orders_provider.dart';
import '../data/order.dart';
import '../widgets/order_card.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  OrderFilter _filter = OrderFilter.active;

  static const _chips = [
    (OrderFilter.active, 'Active'),
    (OrderFilter.pending, 'Pending'),
    (OrderFilter.packed, 'Packed'),
    (OrderFilter.shipped, 'Shipped'),
    (OrderFilter.delivered, 'Delivered'),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(ordersControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ordersControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Text('Orders',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            SizedBox(
              height: 44,
              child: async.maybeWhen(
                data: (orders) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  children: [
                    for (final (filter, label) in _chips)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChoiceChip(
                          label: Text(
                              '$label (${filterOrders(orders, filter).length})'),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                  ],
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load orders'),
                      TextButton(
                        onPressed: () => ref
                            .read(ordersControllerProvider.notifier)
                            .load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (orders) {
                  final filtered = filterOrders(orders, _filter);
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text(
                        'No orders yet.\nConvert an enquiry to start fulfilling.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(ordersControllerProvider.notifier).load(),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, 0, AppSpacing.lg, 96),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: OrderCard(
                          order: filtered[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    OrderDetailScreen(order: filtered[i])),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Write the widget test**

Create `test/features/orders/orders_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/presentation/orders_screen.dart';

import 'orders_controller_test.dart' show FakeOrdersService;

void main() {
  Widget wrap(FakeOrdersService fake) {
    return ProviderScope(
      overrides: [ordersServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: OrdersScreen()),
    );
  }

  testWidgets('shows chips with counts and filters cards', (tester) async {
    final fake = FakeOrdersService(const [
      Order(id: 'o1', orderNumber: 1, customerName: 'Priya', status: 'pending'),
      Order(id: 'o2', orderNumber: 2, customerName: 'Anita', status: 'delivered'),
    ]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    // Active (default) shows only the non-delivered order.
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsNothing);
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Delivered (1)'), findsOneWidget);

    // The Delivered chip sits past the right edge of the horizontal chip row
    // on the default 800px test surface, so scroll it into view before tapping.
    await tester.ensureVisible(find.text('Delivered (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivered (1)'));
    await tester.pumpAndSettle();
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#1'), findsNothing);
  });

  testWidgets('empty state when no orders', (tester) async {
    await tester.pumpWidget(wrap(FakeOrdersService(const [])));
    await tester.pumpAndSettle();
    expect(find.textContaining('No orders yet'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the screen test**

Run: `flutter test test/features/orders/orders_screen_test.dart`
Expected: PASS. (Requires Task 6's `OrderDetailScreen` to exist for the import to resolve — if you are executing strictly in order, write a minimal `OrderDetailScreen` stub first or do Task 6 Step 1–3 before running. The reviewer/executor should implement Task 6 immediately after; the screen import needs it.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/orders/widgets/order_card.dart lib/features/orders/presentation/orders_screen.dart test/features/orders/orders_screen_test.dart
git commit -m "feat(orders): redesigned orders list with filter chips and cards"
```

---

### Task 6: OrderDetailScreen — stepper + lifecycle actions

**Files:**
- Modify (replace contents): `lib/features/orders/presentation/order_detail_screen.dart`
- Test: `test/features/orders/order_detail_test.dart`

Shows the order, a status stepper, a busy-guarded "Mark as \<next>" primary action (packed direct; shipped via a courier/tracking dialog; delivered via confirm), contact actions, and a "Share tracking" button on shipped/delivered orders.

- [ ] **Step 1: Write the detail screen**

Replace the entire contents of `lib/features/orders/presentation/order_detail_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import 'package:orderly_app/shared/widgets/status_pill.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/orders_provider.dart';
import '../data/order.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _busy = false;

  static const _flow = ['pending', 'packed', 'shipped', 'delivered'];

  Order get _live => ref
          .watch(ordersControllerProvider)
          .valueOrNull
          ?.where((o) => o.id == widget.order.id)
          .firstOrNull ??
      widget.order;

  Future<void> _openUri(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the app')));
    }
  }

  Future<void> _advance(Order order) async {
    if (_busy) return;
    final next = nextOrderStatus(order.status);
    if (next == null) return;

    String? courier;
    String? tracking;
    if (next == 'shipped') {
      final result = await _askCourier();
      if (result == null) return;
      courier = result.$1;
      tracking = result.$2;
    } else if (next == 'delivered') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Mark as delivered?'),
          content: const Text(
              'This closes the order. A booked unique piece will be marked sold.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Confirm')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ordersControllerProvider.notifier).advanceTo(
            order,
            next,
            courier: courier,
            trackingNo: tracking,
          );
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Marked as $next')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not update. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns (courier, tracking) or null if cancelled/incomplete.
  Future<(String, String)?> _askCourier() {
    final courierCtl = TextEditingController();
    final trackingCtl = TextEditingController();
    return showDialog<(String, String)?>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Shipping details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: courierCtl,
              decoration: const InputDecoration(labelText: 'Courier'),
            ),
            TextField(
              controller: trackingCtl,
              decoration: const InputDecoration(labelText: 'Tracking number'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final c = courierCtl.text.trim();
              final t = trackingCtl.text.trim();
              if (c.isEmpty || t.isEmpty) return; // both required
              Navigator.pop(d, (c, t));
            },
            child: const Text('Ship'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareTracking(Order order) async {
    final phone = order.customerPhone;
    final validPhone = phone != null && RegExp(r'^[6-9]\d{9}$').hasMatch(phone);
    final msg =
        'Hi ${order.customerName ?? 'there'}, your order #${order.orderNumber ?? ''} '
        'has shipped via ${order.courier ?? ''}. Tracking: ${order.trackingNo ?? ''}.';
    final base = validPhone ? 'https://wa.me/91$phone' : 'https://wa.me/';
    await _openUri(Uri.parse('$base?text=${Uri.encodeComponent(msg)}'));
  }

  @override
  Widget build(BuildContext context) {
    final order = _live;
    final next = nextOrderStatus(order.status);
    final phone = order.customerPhone;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(order.orderNumber != null
            ? '#${order.orderNumber} · ${order.customerName ?? 'Order'}'
            : (order.customerName ?? 'Order')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Status stepper.
          AppCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final s in _flow)
                  Expanded(
                    child: Column(
                      children: [
                        Icon(
                          _flow.indexOf(order.status) >= _flow.indexOf(s)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: _flow.indexOf(order.status) >= _flow.indexOf(s)
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                        const SizedBox(height: 4),
                        Text(s,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (phone != null && phone.isNotEmpty)
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _openUri(Uri.parse('https://wa.me/91$phone')),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openUri(Uri.parse('tel:$phone')),
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: const Text('Call'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          // Items.
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final it in order.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${it.qty} × ${it.name}',
                              style:
                                  const TextStyle(color: AppColors.textPrimary)),
                        ),
                        Text(Money.inr(it.lineTotal),
                            style: const TextStyle(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(Money.inr(order.grandTotal),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    StatusPill(status: order.status),
                    const SizedBox(width: AppSpacing.sm),
                    StatusPill(status: order.paymentStatus),
                  ],
                ),
              ],
            ),
          ),
          if (order.courier != null && order.courier!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${order.courier} · ${order.trackingNo ?? ''}',
                      style: const TextStyle(color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => _shareTracking(order),
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('Share tracking'),
                  ),
                ],
              ),
            ),
          ] else if (order.status == 'shipped') ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => _shareTracking(order),
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: const Text('Share tracking'),
            ),
          ],
          if (next != null) ...[
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: 'Mark as $next',
              loading: _busy,
              onPressed: () => _advance(order),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Write the detail test**

Create `test/features/orders/order_detail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/presentation/order_detail_screen.dart';

import 'orders_controller_test.dart' show FakeOrdersService;

void main() {
  Widget wrap(FakeOrdersService fake, Order order) {
    return ProviderScope(
      overrides: [ordersServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(home: OrderDetailScreen(order: order)),
    );
  }

  testWidgets('primary button reads the next status', (tester) async {
    await tester.pumpWidget(wrap(
      FakeOrdersService(const []),
      const Order(id: 'o1', orderNumber: 5, status: 'pending'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mark as packed'), findsOneWidget);
  });

  testWidgets('delivered order shows no advance button', (tester) async {
    await tester.pumpWidget(wrap(
      FakeOrdersService(const []),
      const Order(id: 'o1', status: 'delivered'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mark as'), findsNothing);
  });

  testWidgets('shipping requires courier and tracking', (tester) async {
    final fake = FakeOrdersService(const []);
    await tester.pumpWidget(wrap(
      fake,
      const Order(id: 'o1', status: 'packed'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark as shipped'));
    await tester.pumpAndSettle();
    // Dialog open; confirm without filling fields does nothing.
    await tester.tap(find.text('Ship'));
    await tester.pumpAndSettle();
    expect(fake.updates, isEmpty); // blocked

    await tester.enterText(find.byType(TextField).at(0), 'DTDC');
    await tester.enterText(find.byType(TextField).at(1), 'TRK9');
    await tester.tap(find.text('Ship'));
    await tester.pumpAndSettle();
    expect(fake.updates.single['status'], 'shipped');
    expect(fake.updates.single['courier'], 'DTDC');
  });

  testWidgets('shipped order offers Share tracking', (tester) async {
    await tester.pumpWidget(wrap(
      FakeOrdersService(const []),
      const Order(
          id: 'o1', status: 'shipped', courier: 'DTDC', trackingNo: 'TRK1'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Share tracking'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the orders test suite**

Run: `flutter test test/features/orders/`
Expected: PASS (models + controller + screen + detail).

- [ ] **Step 4: Commit**

```bash
git add lib/features/orders/presentation/order_detail_screen.dart test/features/orders/order_detail_test.dart
git commit -m "feat(orders): order detail with status stepper and tracking share"
```

---

### Task 7: Retire the legacy order paths

**Files:**
- Delete: `lib/features/orders/widgets/orders_list.dart`
- Modify: `lib/features/leads/controller/leads_controller.dart` (remove `updateOrderStatus` and `updateOrderItems`)

`OrdersList` is unused after the rewrite (the screen builds its own list). `updateOrderStatus`/`updateOrderItems` on the leads shim were only called by the old order card/detail, now replaced. `loadLeads` and `markDone` stay — splash/dashboard/notifications still use them.

- [ ] **Step 1: Delete the dead widget**

```bash
git rm lib/features/orders/widgets/orders_list.dart
```

- [ ] **Step 2: Remove the dead leads methods**

Open `lib/features/leads/controller/leads_controller.dart` and delete the entire `updateOrderStatus(...)` method and the entire `updateOrderItems(...)` method (they start at the `Future<void> updateOrderStatus(` and `Future<void> updateOrderItems(` declarations). Leave `loadLeads` and `markDone` intact. Remove any imports that become unused as a result (run analyze in the next step to find them).

- [ ] **Step 3: Full analyze to catch any dangling references**

Run: `flutter analyze`
Expected: `No issues found!` If analyze reports an unused import in `leads_controller.dart` (e.g. `DraftItem` or the enquiries service if now unused), remove it. If it reports a missing reference elsewhere, that file still imports a removed symbol — fix by pointing it at the new provider (there should be none, since only the rewritten order files used them).

- [ ] **Step 4: Full test suite**

Run: `flutter test`
Expected: all pass (prior suites + the new orders tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/leads/controller/leads_controller.dart
git commit -m "refactor(orders): remove dead legacy order list and leads order methods"
```

---

### Task 8: Final gate + review

**Files:** none (verification + review).

- [ ] **Step 1: Full analyze + tests**

Run: `flutter analyze` (expect `No issues found!`) then `flutter test` (expect all green).

- [ ] **Step 2: Advisors unchanged**

Use the Supabase MCP `get_advisors` (`type: security`). Expected: the same baseline (9 WARN + 1 INFO); no new finding.

- [ ] **Step 3: Final code review**

Dispatch the code-reviewer agent over the whole slice (`git diff <Task-1-commit>^..HEAD`). Focus: `mark_order_delivered` ownership + invoker scoping and that only booked→sold transitions (never re-selling); order_number assignment has no cross-user leakage; every service query scoped by `user_id`; the shipped transition truly can't persist without courier/tracking; the tracking WhatsApp message is URL-encoded and phone validated; no dead references left after the legacy removal. Fix verified findings with implementer subagents and re-review.

- [ ] **Step 4: Finish the branch**

Use superpowers:finishing-a-development-branch. Then deliver a summary + device smoke checklist: convert an enquiry → the order shows a `#number` → Orders tab → Active chip → open it → Mark as packed → Mark as shipped (enter courier + tracking) → Share tracking opens WhatsApp prefilled → Mark as delivered → the order moves to Delivered and the booked unique catalog piece now reads "Sold".

---

## Self-Review

**1. Spec coverage:**
- Typed feature replacing the shim (§2.1, §3) → Tasks 2–4 (models/service/controller) + Task 7 (removal).
- Lifecycle pending→packed→shipped→delivered with courier/tracking (§5) → Task 4 `advanceTo` + Task 6 dialog/stepper.
- Delivery closes booking (piece→sold) (§2.3, §4) → Task 1 `mark_order_delivered` + Task 4 `markDelivered`.
- Sequential order numbers (§2.4, §4) → Task 1 `create_order_with_items` update.
- Redesigned list (chips + cards, default Active) (§7) → Task 5.
- Detail with stepper (§7) → Task 6.
- Share tracking over WhatsApp (§6) → Task 6 `_shareTracking`.
- StatusPill covers the four statuses — already present in `status_pill.dart` (verified), so no extension task is needed (the spec's mention is satisfied by existing code).
- Payment status read-only (§2 non-goals, §7) → shown as a `StatusPill`, never edited.
- Testing (§9) → Tasks 2/4/5/6; migration verification → Task 1 Steps 3–4, Task 8 Step 2.
- Security (§10) → Task 1 (invoker + ownership + revokes), service `user_id` scoping (Task 3), URL-encoded tracking (Task 6).

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to". Every code step is complete. `OrderCard` wraps a plain `AppCard` in an `InkWell` for tap (AppCard has no `onTap` — verified against `app_card.dart`), so Task 5 Step 1 is unconditional. The one remaining conditional (Task 7 Step 3 unused-import cleanup) is explicit. The ordering caveat that Task 5's screen imports Task 6's `OrderDetailScreen` is called out so the executor writes Task 6 before running the whole app analyze (Task 4 Step 4 and Task 5 Step 4 note this).

**3. Type consistency:** `Order`/`OrderItem` fields (Task 2) are read identically in the card/detail (Tasks 5–6). `OrdersService` methods `fetchOrders`/`fetchById`/`updateOrder`/`markDelivered` (Task 3) match `FakeOrdersService` and the controller calls (Task 4). `nextOrderStatus`, `filterOrders`, `OrderFilter`, `ordersServiceProvider`, `ordersControllerProvider`, `OrdersController.advanceTo(order, status, {courier, trackingNo})`/`markDelivered(order)` (Task 4) are used consistently in Tasks 5–6 and the tests. `authUserIdProvider` is re-exported from the provider (Task 4) for the auth-reset test, matching the catalog pattern.
```
