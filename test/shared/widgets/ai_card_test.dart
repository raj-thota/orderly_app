import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/ai_card.dart';

Widget pump(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  testWidgets('renders title and child', (t) async {
    await t.pumpWidget(pump(const AiCard(
      title: 'AI Summary',
      child: Text('Customer prefers evening replies'),
    )));
    expect(find.text('AI Summary'), findsOneWidget);
    expect(find.text('Customer prefers evening replies'), findsOneWidget);
  });

  testWidgets('shows edit button when onEdit provided', (t) async {
    bool tapped = false;
    await t.pumpWidget(pump(AiCard(
      title: 'AI Summary',
      onEdit: () => tapped = true,
      child: const Text('body'),
    )));
    await t.tap(find.byIcon(Icons.edit_outlined));
    expect(tapped, isTrue);
  });

  testWidgets('hides edit button when onEdit null', (t) async {
    await t.pumpWidget(pump(const AiCard(
      title: 'AI Summary',
      child: Text('body'),
    )));
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });
}
