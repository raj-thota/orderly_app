import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/chat_bubble.dart';

Widget pump(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  testWidgets('renders inbound bubble with body text', (t) async {
    await t.pumpWidget(pump(const ChatBubble(
      body: 'I want a saree',
      direction: 'inbound',
    )));
    expect(find.text('I want a saree'), findsOneWidget);
  });

  testWidgets('renders outbound bubble', (t) async {
    await t.pumpWidget(pump(const ChatBubble(
      body: 'Sure! Here is your quote.',
      direction: 'outbound',
    )));
    expect(find.text('Sure! Here is your quote.'), findsOneWidget);
  });

  testWidgets('ai_send bubble shows AI label', (t) async {
    await t.pumpWidget(pump(const ChatBubble(
      body: 'Sent via Closr AI',
      direction: 'outbound',
      isAiSend: true,
    )));
    expect(find.text('Sent via Closr AI'), findsOneWidget);
    expect(find.textContaining('AI'), findsWidgets);
  });
}
