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
