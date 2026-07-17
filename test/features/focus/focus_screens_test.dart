import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/focus_screens.dart';
import 'package:orderly_app/features/focus/data/focus_session.dart';

void main() {
  testWidgets('entry shows scope pill and start callback fires', (tester) async {
    var started = false;
    await tester.pumpWidget(MaterialApp(home: FocusEntryScreen(
      firstName: 'Rahul', taskCount: 5, minutes: 10,
      onStart: () => started = true, onDismiss: () {})));
    expect(find.textContaining('5 tasks'), findsOneWidget);
    await tester.tap(find.byKey(const Key('focus_start')));
    expect(started, isTrue);
  });

  testWidgets('finish shows summary tallies', (tester) async {
    const summary = FocusSummary(tasksCompleted: 5, paymentsFollowedUp: 2,
      amountFollowedUp: 19400, repliesSent: 2, offersSent: 1);
    await tester.pumpWidget(MaterialApp(home: FocusFinishScreen(
      firstName: 'Rahul', summary: summary, onDone: () {})));
    expect(find.textContaining('5'), findsWidgets);
    expect(find.byKey(const Key('focus_done')), findsOneWidget);
  });
}
