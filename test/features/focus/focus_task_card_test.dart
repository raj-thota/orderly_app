import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/focus_task_card.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _pay() => const AiWorkItem(
    id: 'a', kind: 'overdue_payment', priority: 'high', score: 9, title: 't',
    status: 'pending', batchId: 'b1', customerName: 'Aman Gupta', amount: 8597,
    draftMessage: 'Gentle reminder about ₹8,597');

void main() {
  testWidgets('payment card shows title, customer and primary CTA', (tester) async {
    var primaryTapped = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FocusTaskCard(
      item: _pay(),
      onPrimary: () => primaryTapped = true,
      onSkip: () {},
      onMarkDone: () {},
      canSkip: true,
    ))));

    expect(find.text('Aman Gupta'), findsOneWidget);
    expect(find.textContaining('Send'), findsWidgets); // primary verb
    await tester.tap(find.byKey(const Key('focus_primary')));
    expect(primaryTapped, isTrue);
  });

  testWidgets('hides skip when canSkip is false', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FocusTaskCard(
      item: _pay(), onPrimary: () {}, onSkip: () {}, onMarkDone: () {},
      canSkip: false))));
    expect(find.byKey(const Key('focus_skip')), findsNothing);
  });
}
