import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/invoices/controller/invoice_provider.dart';
import 'package:orderly_app/features/invoices/data/invoice_service.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;

class FakeInvoiceService implements InvoiceService {
  int calls = 0;
  bool throwNext = false;
  @override
  Future<String> assignInvoiceNumber(String orderId) async {
    calls++;
    if (throwNext) throw Exception('boom');
    return 'INV-0001';
  }
}

void main() {
  test('prepare assigns a number and reloads orders', () async {
    final inv = FakeInvoiceService();
    final orders = FakeOrdersService(const [Order(id: 'o1')]);
    final c = ProviderContainer(overrides: [
      invoiceServiceProvider.overrideWithValue(inv),
      ordersServiceProvider.overrideWithValue(orders),
    ]);
    addTearDown(c.dispose);

    final number = await c.read(invoiceControllerProvider.notifier)
        .prepare(const Order(id: 'o1'));

    expect(number, 'INV-0001');
    expect(inv.calls, 1);
  });

  test('prepare returns null on failure', () async {
    final inv = FakeInvoiceService()..throwNext = true;
    final orders = FakeOrdersService(const []);
    final c = ProviderContainer(overrides: [
      invoiceServiceProvider.overrideWithValue(inv),
      ordersServiceProvider.overrideWithValue(orders),
    ]);
    addTearDown(c.dispose);

    final number = await c.read(invoiceControllerProvider.notifier)
        .prepare(const Order(id: 'o1'));

    expect(number, isNull);
  });
}
