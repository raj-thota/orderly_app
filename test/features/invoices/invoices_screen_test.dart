import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/invoices/presentation/invoices_screen.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;

void main() {
  Widget wrap(List<Order> orders) => ProviderScope(
        overrides: [
          ordersServiceProvider.overrideWithValue(FakeOrdersService(orders)),
        ],
        child: const MaterialApp(home: InvoicesScreen()),
      );

  testWidgets('lists only invoiced orders', (tester) async {
    await tester.pumpWidget(wrap(const [
      Order(id: 'o1', orderNumber: 1, invoiceNumber: 'INV-0001', customerName: 'Priya'),
      Order(id: 'o2', orderNumber: 2, customerName: 'Anita'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('INV-0001'), findsOneWidget);
    expect(find.text('Anita'), findsNothing);
  });

  testWidgets('shows empty state when nothing is invoiced', (tester) async {
    await tester.pumpWidget(wrap(const [Order(id: 'o1', customerName: 'Anita')]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No invoices yet'), findsOneWidget);
  });
}
