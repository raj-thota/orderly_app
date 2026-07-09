import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/invoices/data/invoice_data.dart';
import 'package:orderly_app/features/invoices/pdf/invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InvoiceData data({bool gst = false, bool paidFull = false, String? upi}) =>
      InvoiceData(
        businessName: 'Rekha Boutique',
        businessPhone: '9876543210',
        gstin: gst ? '29ABCDE1234F1Z5' : null,
        upiId: upi,
        upiName: 'Rekha',
        customerName: 'Priya',
        invoiceNumber: 'INV-0001',
        date: DateTime(2026, 7, 8),
        lines: const [
          InvoiceLine(name: 'Silk Saree', qty: 2, unitPrice: 2500, gstRate: 5, lineTotal: 5000),
        ],
        subtotal: 5000,
        taxable: gst ? 4761.90 : 5000,
        cgst: gst ? 119.05 : 0,
        sgst: gst ? 119.05 : 0,
        grandTotal: 5000,
        paid: paidFull ? 5000 : 2000,
        dues: paidFull ? 0 : 3000,
        upiUri: upi == null ? null : 'upi://pay?pa=$upi&am=3000.00&cu=INR',
      );

  for (final t in InvoiceTemplate.values) {
    test('buildInvoicePdf $t produces non-empty bytes across variants', () async {
      for (final d in [
        data(),
        data(gst: true),
        data(paidFull: true),
        data(upi: 'rekha@upi'),
        data(gst: true, upi: 'rekha@upi'),
      ]) {
        final bytes = await buildInvoicePdf(d, t);
        expect(bytes, isNotEmpty);
      }
    });
  }
}
