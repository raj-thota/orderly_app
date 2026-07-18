import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/invoices/data/invoice_data.dart';

void main() {
  Order order({String? gstRate}) => Order.fromMap({
        'id': 'o1',
        'invoice_number': 'INV-0001',
        'order_number': 1,
        'grand_total': '5250',
        'customers': {'name': 'Priya', 'phone': '9876543210'},
        'created_at': '2026-07-08T00:00:00Z',
        'order_items': [
          {'name': 'Saree', 'qty': 1, 'unit_price': '5250', 'line_total': '5250',
           'gst_rate': ?gstRate},
        ],
        'payments': [
          {'amount': '2000'},
        ],
      });

  test('no GSTIN: no tax, subtotal equals grand total', () {
    final d = InvoiceData.fromOrder(order(gstRate: '5'),
        const BusinessProfile(name: 'Shop')); // no gstin
    expect(d.hasGst, isFalse);
    expect(d.cgst, 0);
    expect(d.sgst, 0);
    expect(d.subtotal, 5250);
    expect(d.grandTotal, 5250);
  });

  test('with GSTIN: tax extracted inclusive, total unchanged', () {
    final d = InvoiceData.fromOrder(order(gstRate: '5'),
        const BusinessProfile(name: 'Shop', gstin: '29ABCDE1234F1Z5'));
    expect(d.hasGst, isTrue);
    // 5250 inclusive of 5% => taxable 5000, tax 250, split 125/125.
    expect(d.taxable, closeTo(5000, 0.01));
    expect(d.cgst, closeTo(125, 0.01));
    expect(d.sgst, closeTo(125, 0.01));
    expect(d.grandTotal, 5250);
  });

  test('carries paid/dues, number, customer and upi', () {
    final d = InvoiceData.fromOrder(order(),
        const BusinessProfile(name: 'Shop', upiId: 'shop@upi', upiName: 'Shop'));
    expect(d.invoiceNumber, 'INV-0001');
    expect(d.paid, 2000);
    expect(d.dues, 3250);
    expect(d.customerName, 'Priya');
    expect(d.upiUri, contains('pa=shop@upi'));
  });

  test('InvoiceLine.displayName appends label for non-product types', () {
    const product = InvoiceLine(
        name: 'Saree', qty: 1, unitPrice: 100, gstRate: 0, lineTotal: 100,
        type: 'product');
    const service = InvoiceLine(
        name: 'Haircut', qty: 1, unitPrice: 300, gstRate: 0, lineTotal: 300,
        type: 'service');
    expect(product.displayName, 'Saree');
    expect(service.displayName, 'Haircut · Service');
  });
}
