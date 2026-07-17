import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/focus_overlays.dart';

void main() {
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
}
