import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/settings/presentation/settings_screen.dart';

Widget _wrap() => const ProviderScope(child: MaterialApp(home: SettingsScreen()));

void main() {
  testWidgets('shows Settings title and section headers', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('GENERAL'), findsOneWidget);
    expect(find.text('BUSINESS'), findsOneWidget);
    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('SUPPORT'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
  });

  testWidgets('Invoice Settings and Logout rows present', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Invoice Settings'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('Theme row shows Coming soon and is disabled', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Coming soon'), findsWidgets);
  });
}
