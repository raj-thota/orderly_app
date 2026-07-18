import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/widgets/product_tile.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, height: 280, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows name, INR price and availability pill for a unique piece',
      (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(
        name: 'Banarasi Saree',
        price: 4500,
        isUnique: true,
        pieceStatus: 'available',
      ),
      onTap: () {},
    )));
    expect(find.text('Banarasi Saree'), findsOneWidget);
    expect(find.text('₹4,500'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('shows stock count for a stocked item', (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Cotton Kurti', price: 799, qtyOnHand: 4),
      onTap: () {},
    )));
    expect(find.text('4 in stock'), findsOneWidget);
  });

  testWidgets('shows sold-out state for stocked item with zero qty',
      (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Cotton Kurti', price: 799, qtyOnHand: 0),
      onTap: () {},
    )));
    expect(find.text('Out of stock'), findsOneWidget);
  });

  testWidgets('imageless product shows the type placeholder', (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Cotton Kurti', price: 799),
      onTap: () {},
    )));
    expect(find.text('C'), findsOneWidget); // first-letter placeholder
    expect(find.byIcon(Icons.photo_outlined), findsNothing);
  });

  testWidgets('shows the type badge', (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'Haircut', price: 300, type: 'service'),
      onTap: () {},
    )));
    expect(find.text('Service'), findsOneWidget);
  });

  testWidgets('non-product type hides stock text', (tester) async {
    await tester.pumpWidget(_wrap(ProductTile(
      product: Product(name: 'E-book', price: 199, type: 'digital', qtyOnHand: 0),
      onTap: () {},
    )));
    expect(find.text('Out of stock'), findsNothing);
  });
}
