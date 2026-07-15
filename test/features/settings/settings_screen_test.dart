import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/settings/presentation/settings_screen.dart';

Widget _wrap() => const ProviderScope(
      child: MaterialApp(home: SettingsScreen()),
    );

void main() {
  testWidgets('shows Settings title', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('shows Business Profile row', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Business Profile'), findsOneWidget);
  });

  testWidgets('shows Invoice Settings row', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Invoice Settings'), findsOneWidget);
  });

  testWidgets('shows Data & Privacy row', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Data & Privacy'), findsOneWidget);
  });

  testWidgets('shows Help & Support row', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Help & Support'), findsOneWidget);
  });

  testWidgets('shows Sign Out row', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Sign Out'), findsOneWidget);
  });
}
