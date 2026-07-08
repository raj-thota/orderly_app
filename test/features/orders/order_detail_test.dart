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
