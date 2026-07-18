import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/orders/widgets/order_item_row_card.dart';

Widget _wrap(Widget child) => ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('editable card shows stepper + line total + badge', (tester) async {
    var qty = 2;
    await tester.pumpWidget(_wrap(OrderItemRowCard(
      name: 'Silk Saree',
      type: ItemType.product,
      imagePath: null,
      unitPrice: 2499,
      qty: qty,
      onQtyChanged: (v) => qty = v,
      onRemove: () {},
    )));
    expect(find.text('Silk Saree'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('₹4,998'), findsOneWidget); // 2 x 2499
    await tester.tap(find.byIcon(Icons.add));
    expect(qty, 3);
  });

  testWidgets('read-only card hides stepper + remove', (tester) async {
    await tester.pumpWidget(_wrap(const OrderItemRowCard(
      name: 'Haircut',
      type: ItemType.service,
      imagePath: null,
      unitPrice: 300,
      qty: 1,
    )));
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('₹300'), findsOneWidget);
  });
}
