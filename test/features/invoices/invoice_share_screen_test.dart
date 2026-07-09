import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/invoices/controller/invoice_provider.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_share_screen.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;
import 'invoice_controller_test.dart' show FakeInvoiceService;

void main() {
  testWidgets('renders template chips with the profile default preselected',
      (tester) async {
    final order = Order.fromMap({
      'id': 'o1', 'order_number': 1, 'invoice_number': 'INV-0001',
      'grand_total': '5000',
      'order_items': [
        {'name': 'Saree', 'qty': 1, 'unit_price': '5000', 'line_total': '5000'},
      ],
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        invoiceServiceProvider.overrideWithValue(FakeInvoiceService()),
        ordersServiceProvider.overrideWithValue(FakeOrdersService([order])),
        businessProfileProvider.overrideWith(
            (ref) async => const BusinessProfile(name: 'Shop', invoiceTemplate: 'minimal')),
      ],
      child: MaterialApp(home: InvoiceShareScreen(order: order)),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Minimal'), findsOneWidget);
    expect(find.text('Boutique'), findsOneWidget);

    // Default 'minimal' selected.
    final minimal = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Minimal'));
    expect(minimal.selected, isTrue);

    await tester.tap(find.text('Classic'));
    await tester.pump(const Duration(milliseconds: 200));
    final classic = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Classic'));
    expect(classic.selected, isTrue);
  });
}
