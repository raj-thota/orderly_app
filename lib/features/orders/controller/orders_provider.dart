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
