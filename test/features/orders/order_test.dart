import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/data/order.dart';

void main() {
  test('fromMap flattens customer, parses items and totals', () {
    final order = Order.fromMap({
      'id': 'o1',
      'order_number': 1042,
      'customer_id': 'c1',
      'customers': {'name': 'Priya', 'phone': '9876543210'},
      'status': 'packed',
      'courier': 'DTDC',
      'tracking_no': 'TRK1',
      'payment_status': 'unpaid',
      'grand_total': '5500',
      'subtotal': '5500',
      'notes': 'gift wrap',
      'order_items': [
        {'name': 'Silk Saree', 'qty': 2, 'unit_price': '2500', 'line_total': '5000'},
        {'name': 'Blouse', 'qty': 1, 'unit_price': '500', 'line_total': '500'},
      ],
    });

    expect(order.orderNumber, 1042);
    expect(order.customerName, 'Priya');
    expect(order.customerPhone, '9876543210');
    expect(order.status, 'packed');
    expect(order.courier, 'DTDC');
    expect(order.trackingNo, 'TRK1');
    expect(order.paymentStatus, 'unpaid');
    expect(order.grandTotal, 5500);
    expect(order.items, hasLength(2));
    expect(order.items.first.name, 'Silk Saree');
    expect(order.items.first.qty, 2);
    expect(order.items.first.lineTotal, 5000);
  });

  test('fromMap tolerates missing joins and fields', () {
    final order = Order.fromMap({'id': 'o2'});
    expect(order.customerName, isNull);
    expect(order.status, 'confirmed'); // default (was 'pending')
    expect(order.paymentStatus, 'unpaid'); // default
    expect(order.grandTotal, 0);
    expect(order.items, isEmpty);
  });

  test('fromMap parses cancelled status', () {
    final order = Order.fromMap({'id': 'o3', 'status': 'cancelled'});
    expect(order.status, 'cancelled');
  });

  test('fromMap reads invoice_number and item gst_rate', () {
    final order = Order.fromMap({
      'id': 'o1',
      'invoice_number': 'INV-0042',
      'order_items': [
        {'name': 'Silk Saree', 'qty': 1, 'unit_price': '2500', 'gst_rate': '5'},
      ],
    });
    expect(order.invoiceNumber, 'INV-0042');
    expect(order.items.single.gstRate, 5);
  });

  test('invoiceNumber is null and gstRate defaults to 0 when absent', () {
    final order = Order.fromMap({'id': 'o2', 'order_items': [
      {'name': 'X', 'qty': 1},
    ]});
    expect(order.invoiceNumber, isNull);
    expect(order.items.single.gstRate, 0);
  });
}
