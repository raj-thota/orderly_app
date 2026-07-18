import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';

Widget _wrap() => ProviderScope(
      overrides: [
        businessProfileProvider.overrideWith((ref) async =>
            const BusinessProfile(
              name: 'Sarees by Anu',
              ownerName: 'Anu',
              upiId: 'anu@upi',
              city: 'Surat',
            )),
        userProfileProvider.overrideWith((ref) async =>
            <String, dynamic>{'email': 'anu@shop.com'}),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    );

void main() {
  testWidgets('renders grouped business profile sections', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Business Information'), findsOneWidget);
    expect(find.text('Business Identity'), findsOneWidget);
    expect(find.text('Payment Details'), findsOneWidget);
    expect(find.text('Sarees by Anu'), findsWidgets);
  });

  testWidgets('does not show logout or help (moved to Settings)', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Logout'), findsNothing);
    expect(find.text('Help & Support'), findsNothing);
  });

  testWidgets('shows UPI QR when upiId present', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('upi-qr')), findsOneWidget);
  });
}
