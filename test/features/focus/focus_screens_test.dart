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

  testWidgets('success overlay fires onDone after animation', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FocusSuccessOverlay(
      progress: 0.6, line: 'Nice work! 2 more to go.',
      onDone: () => done = true))));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(done, isTrue);
  });

  testWidgets('empty screen fires back-home', (tester) async {
    var back = false;
    await tester.pumpWidget(MaterialApp(home: FocusEmptyScreen(
      onBackHome: () => back = true)));
    expect(find.textContaining('caught up'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    expect(back, isTrue);
  });

  testWidgets('entry resume variant shows Resume label', (tester) async {
    await tester.pumpWidget(MaterialApp(home: FocusEntryScreen(
      firstName: 'Rahul', taskCount: 5, minutes: 10, resumeLeft: 2,
      onStart: () {}, onDismiss: () {})));
    expect(find.textContaining('Resume'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
  });
}
