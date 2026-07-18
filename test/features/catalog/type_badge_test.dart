import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/widgets/type_badge.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows label + icon for the type', (tester) async {
    await tester.pumpWidget(_wrap(const TypeBadge(type: ItemType.service)));
    expect(find.text('Service'), findsOneWidget);
    expect(find.byIcon(Icons.handyman_outlined), findsOneWidget);
  });

  testWidgets('compact hides the label but keeps the icon', (tester) async {
    await tester.pumpWidget(
        _wrap(const TypeBadge(type: ItemType.digital, compact: true)));
    expect(find.text('Digital Product'), findsNothing);
    expect(find.byIcon(Icons.devices_outlined), findsOneWidget);
  });
}
