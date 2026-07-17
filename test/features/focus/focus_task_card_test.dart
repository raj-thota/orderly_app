import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/focus_task_card.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _pay() => const AiWorkItem(
    id: 'a', kind: 'overdue_payment', priority: 'high', score: 9, title: 't',
    status: 'pending', batchId: 'b1', customerName: 'Aman Gupta', amount: 8597,
    draftMessage: 'Gentle reminder about ₹8,597');

AiWorkItem _other() => const AiWorkItem(
    id: 'b', kind: 'unknown_task', priority: 'low', score: 1, title: 't2',
    status: 'pending', batchId: 'b2', customerName: 'Ravi Kumar');

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

  testWidgets('other-group card shows Open in workspace CTA', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FocusTaskCard(
      item: _other(), onPrimary: () {}, onSkip: () {}, onMarkDone: () {},
      canSkip: true))));
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Open in workspace'), findsOneWidget);
  });

  testWidgets('customer chip survives empty customerName string', (tester) async {
    const item = AiWorkItem(
      id: 'c', kind: 'overdue_payment', priority: 'low', score: 1, title: 't3',
      status: 'pending', batchId: 'b3', customerName: '');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FocusTaskCard(
      item: item, onPrimary: () {}, onSkip: () {}, onMarkDone: () {},
      canSkip: false))));
    // Should render without crashing; falls back to 'Customer'
    expect(find.text('Customer'), findsOneWidget);
  });
}
