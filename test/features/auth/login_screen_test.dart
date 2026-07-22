import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/auth/presentation/login_screen.dart';

Widget _wrap() => const ProviderScope(
      child: MaterialApp(home: LoginScreen()),
    );

void main() {
  testWidgets('shows Google sign-in button', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('google_signin_btn')), findsOneWidget);
  });

  testWidgets('phone OTP entry is hidden', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('phone_field')), findsNothing);
    expect(find.byKey(const Key('get_otp_btn')), findsNothing);
  });

  testWidgets('shows Apple sign-in button on iOS', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await t.pumpWidget(_wrap());
      await t.pumpAndSettle();
      expect(find.byKey(const Key('apple_signin_btn')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('hides Apple sign-in button off iOS', (t) async {
    // Widget tests default to the Android platform, so no override needed.
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('apple_signin_btn')), findsNothing);
  });
}
