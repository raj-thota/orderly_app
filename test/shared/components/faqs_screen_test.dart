import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/components/faqs_screen.dart';

void main() {
  testWidgets('FAQs page renders questions', (t) async {
    await t.pumpWidget(const MaterialApp(home: FaqsScreen()));
    await t.pumpAndSettle();
    expect(find.text('FAQs'), findsOneWidget); // app bar title
    expect(find.text('What is Focus Mode?'), findsOneWidget);
  });

  testWidgets('tapping a question expands its answer', (t) async {
    await t.pumpWidget(const MaterialApp(home: FaqsScreen()));
    await t.pumpAndSettle();
    await t.tap(find.text('What is Focus Mode?'));
    await t.pumpAndSettle();
    expect(find.textContaining('Start My Work'), findsOneWidget);
  });
}
