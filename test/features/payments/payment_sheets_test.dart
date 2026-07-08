import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/payments/widgets/record_payment_sheet.dart';
import 'package:orderly_app/features/payments/widgets/upi_collect_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('RecordPaymentSheet returns amount and chosen method', (tester) async {
    double? gotAmount;
    String? gotMethod;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RecordPaymentSheet(
          onSave: (amount, method) async {
            gotAmount = amount;
            gotMethod = method;
            return true;
          },
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), '1500');
    await tester.tap(find.text('Cash'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gotAmount, 1500);
    expect(gotMethod, 'cash');
  });

  testWidgets('RecordPaymentSheet blocks save until amount > 0', (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RecordPaymentSheet(
          onSave: (amount, method) async {
            called = true;
            return true;
          },
        ),
      ),
    ));

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(called, isFalse);
  });

  testWidgets('UpiCollectSheet renders a QR and shares on tap', (tester) async {
    var shared = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpiCollectSheet(
          amount: 2500,
          upiUri: 'upi://pay?pa=x@upi&am=2500.00&cu=INR',
          vpa: 'x@upi',
          vpaName: 'Shop',
          onShareWhatsApp: () => shared = true,
        ),
      ),
    ));

    expect(find.byType(QrImageView), findsOneWidget);
    await tester.tap(find.text('Send payment link on WhatsApp'));
    expect(shared, isTrue);
  });
}
