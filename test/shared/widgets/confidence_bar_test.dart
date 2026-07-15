import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/confidence_bar.dart';

Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('displays percentage text', (tester) async {
    await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 0.75)));
    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('rounds to nearest percent', (tester) async {
    await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 0.916)));
    expect(find.text('92%'), findsOneWidget);
  });

  testWidgets('displays 0% for zero confidence', (tester) async {
    await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 0)));
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('displays 100% for perfect confidence', (tester) async {
    await tester.pumpWidget(wrap(const ConfidenceBar(confidence: 1)));
    expect(find.text('100%'), findsOneWidget);
  });
}
