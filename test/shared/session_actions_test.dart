import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/utils/session_actions.dart';

void main() {
  testWidgets('shows confirm dialog and cancels cleanly', (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => confirmAndLogout(context, ref),
                child: const Text('Logout'),
              ),
            ),
          );
        }),
      ),
    ));
    await t.tap(find.text('Logout'));
    await t.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Log out?'), findsNothing);
  });
}
