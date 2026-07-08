import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/payments/data/payment.dart';

void main() {
  test('Payment.fromMap parses amount, method and paidAt', () {
    final p = Payment.fromMap({
      'amount': '2500',
      'method': 'cash',
      'paid_at': '2026-07-08T10:00:00Z',
    });
    expect(p.amount, 2500);
    expect(p.method, 'cash');
    expect(p.paidAt, isNotNull);
  });

  test('Payment.fromMap defaults tolerate missing fields', () {
    final p = Payment.fromMap({});
    expect(p.amount, 0);
    expect(p.method, 'upi');
    expect(p.paidAt, isNull);
  });

  test('Order.fromMap parses payments and computes paid/dues', () {
    final o = Order.fromMap({
      'id': 'o1',
      'grand_total': '5000',
      'payments': [
        {'amount': '2000', 'method': 'upi'},
        {'amount': '500', 'method': 'cash'},
      ],
    });
    expect(o.payments, hasLength(2));
    expect(o.paidTotal, 2500);
    expect(o.dues, 2500);
  });

  test('dues floors at zero on overpayment', () {
    final o = Order.fromMap({
      'id': 'o1',
      'grand_total': '1000',
      'payments': [
        {'amount': '1200'},
      ],
    });
    expect(o.paidTotal, 1200);
    expect(o.dues, 0);
  });

  test('no payments means dues equals grand total', () {
    final o = Order.fromMap({'id': 'o1', 'grand_total': '800'});
    expect(o.paidTotal, 0);
    expect(o.dues, 800);
  });
}
