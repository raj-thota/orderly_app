import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/orders/widgets/item_picker_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final products = [
    Product(name: 'Silk Saree', price: 2499, type: 'product'),
    Product(name: 'Haircut', price: 300, type: 'service'),
  ];

  testWidgets('filters the grid by search text', (tester) async {
    await tester.pumpWidget(_wrap(ItemPickerSheet(
      products: products,
      onPick: (_) {},
      onCustom: () {},
    )));
    expect(find.text('Silk Saree'), findsOneWidget);
    expect(find.text('Haircut'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'hair');
    await tester.pump();
    expect(find.text('Silk Saree'), findsNothing);
    expect(find.text('Haircut'), findsOneWidget);
  });

  testWidgets('tapping a tile fires onPick', (tester) async {
    Product? picked;
    await tester.pumpWidget(_wrap(ItemPickerSheet(
      products: products,
      onPick: (p) => picked = p,
      onCustom: () {},
    )));
    await tester.tap(find.text('Silk Saree'));
    expect(picked?.name, 'Silk Saree');
  });
}
