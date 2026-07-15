import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/auth/presentation/login_screen.dart';

Widget _wrap() => const ProviderScope(
      child: MaterialApp(home: LoginScreen()),
    );

void main() {
  testWidgets('shows phone input field', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('phone_field')), findsOneWidget);
  });

  testWidgets('shows Get OTP button', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('get_otp_btn')), findsOneWidget);
  });

  testWidgets('Get OTP button disabled when phone empty', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    final btn = t.widget<FilledButton>(find.byKey(const Key('get_otp_btn')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Get OTP button enabled after entering 10-digit phone', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('phone_field')), '9876543210');
    await t.pump();

    final btn = t.widget<FilledButton>(find.byKey(const Key('get_otp_btn')));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('does not show Google or Apple login buttons', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.textContaining('Continue with Google'), findsNothing);
    expect(find.textContaining('Sign in with Apple'), findsNothing);
    expect(find.textContaining('Enter password'), findsNothing);
  });
}
