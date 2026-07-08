import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/payments/controller/payments_provider.dart';
import 'package:orderly_app/features/payments/data/payments_service.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;

class FakePaymentsService implements PaymentsService {
  final List<Map<String, dynamic>> recorded = [];
  bool throwNext = false;

  @override
  Future<void> recordPayment(
      String orderId, double amount, String method) async {
    if (throwNext) throw Exception('boom');
    recorded.add({'order': orderId, 'amount': amount, 'method': method});
  }
}

void main() {
  test('recordPayment calls the service and reloads orders', () async {
    final payFake = FakePaymentsService();
    final ordersFake = FakeOrdersService(const [Order(id: 'o1', grandTotal: 5000)]);
    final c = ProviderContainer(overrides: [
      paymentsServiceProvider.overrideWithValue(payFake),
      ordersServiceProvider.overrideWithValue(ordersFake),
    ]);
    addTearDown(c.dispose);
    await c.read(ordersControllerProvider.notifier).load();

    final ok = await c
        .read(paymentsControllerProvider.notifier)
        .recordPayment('o1', 2500, 'upi');

    expect(ok, isTrue);
    expect(payFake.recorded.single,
        {'order': 'o1', 'amount': 2500.0, 'method': 'upi'});
  });

  test('recordPayment returns false when the service throws', () async {
    final payFake = FakePaymentsService()..throwNext = true;
    final ordersFake = FakeOrdersService(const []);
    final c = ProviderContainer(overrides: [
      paymentsServiceProvider.overrideWithValue(payFake),
      ordersServiceProvider.overrideWithValue(ordersFake),
    ]);
    addTearDown(c.dispose);

    final ok = await c
        .read(paymentsControllerProvider.notifier)
        .recordPayment('o1', 100, 'cash');

    expect(ok, isFalse);
  });
}
