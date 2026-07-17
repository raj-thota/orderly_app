import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/providers/auth_providers.dart';

import '../data/order.dart';
import '../data/orders_service.dart';

export 'package:orderly_app/core/providers/auth_providers.dart'
    show authUserIdProvider;

enum OrderFilter { active, confirmed, packed, shipped, delivered, cancelled }

/// The next status in the linear lifecycle, or null when terminal.
String? nextOrderStatus(String current) {
  const flow = ['confirmed', 'packed', 'shipped', 'delivered'];
  final i = flow.indexOf(current);
  if (i < 0 || i >= flow.length - 1) return null;
  return flow[i + 1];
}

/// Filters orders for a chip. `active` = anything not delivered or cancelled.
List<Order> filterOrders(List<Order> orders, OrderFilter filter) {
  switch (filter) {
    case OrderFilter.active:
      return orders
          .where((o) => o.status != 'delivered' && o.status != 'cancelled')
          .toList();
    case OrderFilter.confirmed:
      return orders.where((o) => o.status == 'confirmed').toList();
    case OrderFilter.packed:
      return orders.where((o) => o.status == 'packed').toList();
    case OrderFilter.shipped:
      return orders.where((o) => o.status == 'shipped').toList();
    case OrderFilter.delivered:
      return orders.where((o) => o.status == 'delivered').toList();
    case OrderFilter.cancelled:
      return orders.where((o) => o.status == 'cancelled').toList();
  }
}

final ordersServiceProvider = Provider<OrdersService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return OrdersService();
});

final ordersControllerProvider =
    StateNotifierProvider<OrdersController, AsyncValue<List<Order>>>((ref) {
  return OrdersController(ref.watch(ordersServiceProvider))..load();
});

class OrdersController extends StateNotifier<AsyncValue<List<Order>>> {
  OrdersController(this._service) : super(const AsyncValue.loading());

  final OrdersService _service;

  Future<void> load() async {
    final next = await AsyncValue.guard(_service.fetchOrders);
    if (!mounted) return; // disposed mid-fetch by an auth-driven rebuild
    state = next;
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
