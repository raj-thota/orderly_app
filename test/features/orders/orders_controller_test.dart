import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';

class FakeOrdersService implements OrdersService {
  FakeOrdersService(List<Order> seed) : _rows = List.of(seed);
  final List<Order> _rows;
  final List<Map<String, dynamic>> updates = [];
  final List<String> delivered = [];
  final List<String> cancelled = [];

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
  @override
  Future<void> cancelOrder(String id) async => cancelled.add(id);
  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<CreateOrderItem> items,
    double discount = 0,
    double shippingFee = 0,
    DateTime? expectedDate,
    String? notes,
  }) async => '';
}

/// Fetch that never resolves until [gate] is completed, so a test can dispose
/// the controller while a load is mid-flight.
class GatedOrdersService extends FakeOrdersService {
  GatedOrdersService(this.gate) : super(const []);
  final Completer<List<Order>> gate;
  @override
  Future<List<Order>> fetchOrders() => gate.future;
}

void main() {
  test('nextOrderStatus advances linearly and stops at delivered', () {
    expect(nextOrderStatus('confirmed'), 'packed');
    expect(nextOrderStatus('packed'), 'shipped');
    expect(nextOrderStatus('shipped'), 'delivered');
    expect(nextOrderStatus('delivered'), isNull);
    expect(nextOrderStatus('cancelled'), isNull);
  });

  test('filterOrders Active excludes delivered and cancelled', () {
    final orders = const [
      Order(id: 'a', status: 'confirmed'),
      Order(id: 'b', status: 'shipped'),
      Order(id: 'c', status: 'delivered'),
      Order(id: 'd', status: 'cancelled'),
    ];
    expect(filterOrders(orders, OrderFilter.active).map((o) => o.id),
        ['a', 'b']);
    expect(filterOrders(orders, OrderFilter.delivered).map((o) => o.id),
        ['c']);
    expect(filterOrders(orders, OrderFilter.confirmed).map((o) => o.id), ['a']);
    expect(filterOrders(orders, OrderFilter.cancelled).map((o) => o.id), ['d']);
  });

  ProviderContainer makeContainer(FakeOrdersService fake) {
    final container = ProviderContainer(overrides: [
      ordersServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('load exposes orders', () async {
    final fake = FakeOrdersService(const [Order(id: 'o1', status: 'confirmed')]);
    final c = makeContainer(fake);
    await c.read(ordersControllerProvider.notifier).load();
    expect(c.read(ordersControllerProvider).value, hasLength(1));
  });

  test('advanceTo packed sends a status-only update', () async {
    final fake = FakeOrdersService(const [Order(id: 'o1', status: 'confirmed')]);
    final c = makeContainer(fake);
    final controller = c.read(ordersControllerProvider.notifier);
    await controller.load();
    await controller.advanceTo(const Order(id: 'o1', status: 'confirmed'), 'packed');
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

  test('load does not throw when disposed mid-fetch', () async {
    // An auth change rebuilds the service provider, disposing this controller
    // while its constructor-kicked load() is still awaiting the server.
    final gate = Completer<List<Order>>();
    final controller = OrdersController(GatedOrdersService(gate));
    final loadFuture = controller.load();
    controller.dispose();
    gate.complete(const [Order(id: 'o1')]);
    await expectLater(loadFuture, completes);
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
