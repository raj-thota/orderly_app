import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_settings_screen.dart';

Widget _wrap() => ProviderScope(
      overrides: [
        businessProfileProvider.overrideWith((ref) async =>
            const BusinessProfile(
              name: 'Shop',
              invoicePrefix: 'INV-',
              nextInvoiceNumber: 42,
              currency: 'INR',
              invoiceFooter: 'Thank you',
            )),
      ],
      child: const MaterialApp(home: InvoiceSettingsScreen()),
    );

void main() {
  testWidgets('renders invoice settings fields and preview', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Invoice Settings'), findsWidgets);
    expect(find.text('Invoice Prefix'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.textContaining('INV-0042'), findsWidgets);
  });
}
