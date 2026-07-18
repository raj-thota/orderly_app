import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/widgets/product_image.dart';

Widget _wrap(Widget child) => ProviderScope(
    child: MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 120, height: 120, child: child)))));

void main() {
  testWidgets('no path + type renders the type placeholder', (tester) async {
    await tester.pumpWidget(_wrap(
        const ProductImage(path: null, type: ItemType.service, name: 'Haircut')));
    expect(find.text('H'), findsOneWidget);
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
  });

  testWidgets('no path + no type keeps the neutral placeholder', (tester) async {
    await tester.pumpWidget(_wrap(const ProductImage(path: null)));
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
  });
}
