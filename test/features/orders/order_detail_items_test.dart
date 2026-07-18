import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/presentation/order_detail_screen.dart';

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: child));

void main() {
  testWidgets('renders items as row cards with type badges', (tester) async {
    final order = Order(
      id: 'o1',
      orderNumber: 7,
      grandTotal: 4998,
      items: const [
        OrderItem(name: 'Silk Saree', unitPrice: 2499, qty: 2, type: 'product'),
      ],
    );
    await tester.pumpWidget(_wrap(OrderDetailScreen(order: order)));
    await tester.pumpAndSettle();
    expect(find.text('Silk Saree'), findsOneWidget);
    expect(find.text('Product'), findsWidgets); // badge label
    expect(find.byIcon(Icons.close), findsNothing); // read-only, no remove
  });
}
