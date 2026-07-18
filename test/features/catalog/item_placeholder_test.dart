import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/widgets/item_placeholder.dart';

Widget _wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 120, height: 120, child: child))));

void main() {
  testWidgets('shows uppercased first letter + type icon', (tester) async {
    await tester.pumpWidget(
        _wrap(const ItemPlaceholder(type: ItemType.product, name: 'silk saree')));
    expect(find.text('S'), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
  });

  testWidgets('falls back to ? for an empty name', (tester) async {
    await tester.pumpWidget(
        _wrap(const ItemPlaceholder(type: ItemType.other, name: '   ')));
    expect(find.text('?'), findsOneWidget);
  });
}
