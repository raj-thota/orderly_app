import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/presentation/business_hub_screen.dart';

void main() {
  testWidgets('shows the four hub destinations', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: BusinessHubScreen()),
    ));

    expect(find.text('Business'), findsOneWidget);
    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Business Profile'), findsOneWidget);
    expect(find.text('Go Pro'), findsOneWidget);
  });
}
