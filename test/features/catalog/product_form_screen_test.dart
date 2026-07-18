import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/presentation/product_form_screen.dart';

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: child));

void main() {
  testWidgets('shows SKU + category for product type', (tester) async {
    await tester.pumpWidget(_wrap(const ProductFormScreen()));
    await tester.pumpAndSettle();
    expect(find.text('SKU'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Duration'), findsNothing);
  });

  testWidgets('switching to Service swaps to duration', (tester) async {
    await tester.pumpWidget(_wrap(const ProductFormScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Service'));
    await tester.pumpAndSettle();
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('SKU'), findsNothing);
    expect(find.text('One-of-a-kind piece'), findsNothing);
  });

  testWidgets('editing an existing service preselects its type', (tester) async {
    await tester.pumpWidget(_wrap(ProductFormScreen(
        existing: Product(name: 'Facial', price: 500, type: 'service', duration: '60 min'))));
    await tester.pumpAndSettle();
    expect(find.text('Duration'), findsOneWidget);
  });
}
