import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/focus_overlays.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Exit Dialog
  // ---------------------------------------------------------------------------

  testWidgets('exit dialog returns true on Leave, false on Keep going',
      (tester) async {
    late bool? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => result = await showFocusExitDialog(ctx, done: 1, total: 5),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Leave Focus Mode'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('exit dialog returns false on Keep going', (tester) async {
    late bool result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => result = await showFocusExitDialog(ctx, done: 2, total: 5),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('exit dialog barrier-dismiss returns false (stay in focus)',
      (tester) async {
    late bool result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => result = await showFocusExitDialog(ctx, done: 0, total: 5),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Tap the barrier (outside the dialog) to dismiss it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('exit dialog shows done/total in body copy', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => showFocusExitDialog(ctx, done: 3, total: 7),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 of 7'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Skip Sheet
  // ---------------------------------------------------------------------------

  testWidgets('skip sheet returns true on Skip', (tester) async {
    late bool result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async =>
            result = await showFocusSkipSheet(ctx, customerName: 'Aman'),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Skip this for now'), findsOneWidget);
    await tester.tap(find.text('Skip →'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('skip sheet returns false on Keep task', (tester) async {
    late bool result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async =>
            result = await showFocusSkipSheet(ctx, customerName: 'Priya'),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep task'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('skip sheet shows customerName in body', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => showFocusSkipSheet(ctx, customerName: 'Suresh'),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Suresh's task"), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Error Toast
  // ---------------------------------------------------------------------------

  testWidgets('focusErrorToast renders customerName and fires onRetry',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: focusErrorToast(
          customerName: 'Aman',
          onRetry: () => retried = true,
        ),
      ),
    ));
    expect(find.textContaining('Aman'), findsOneWidget);
    expect(find.textContaining('draft is safe'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('FocusErrorToast class renders same as function form',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FocusErrorToast(
          customerName: 'Priya',
          onRetry: () => retried = true,
        ),
      ),
    ));
    expect(find.textContaining('Priya'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });
}
