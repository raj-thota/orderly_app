import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/payments/data/payment.dart';
import 'package:orderly_app/features/today/data/recent_activity.dart';

void main() {
  final base = DateTime(2026, 7, 15, 10);

  test('orders without timestamps are skipped', () {
    expect(buildRecentActivity(const [Order(grandTotal: 100)]), isEmpty);
  });

  test('flattens orders and payments newest first', () {
    final orders = [
      Order(
        customerName: 'Meena',
        grandTotal: 9500,
        createdAt: base,
        payments: [
          Payment(amount: 4000, paidAt: base.add(const Duration(hours: 2))),
        ],
      ),
      Order(
        customerName: 'Aman',
        grandTotal: 500,
        createdAt: base.add(const Duration(hours: 1)),
      ),
    ];

    final feed = buildRecentActivity(orders);

    expect(feed, hasLength(3));
    expect(feed[0].kind, ActivityKind.paymentReceived);
    expect(feed[0].amount, 4000);
    expect(feed[1].kind, ActivityKind.orderCreated);
    expect(feed[1].order.customerName, 'Aman');
    expect(feed[2].kind, ActivityKind.orderCreated);
    expect(feed[2].order.customerName, 'Meena');
    expect(feed[2].amount, 9500);
  });

  test('respects the limit', () {
    final orders = [
      for (var i = 0; i < 8; i++)
        Order(grandTotal: 100, createdAt: base.add(Duration(minutes: i))),
    ];

    expect(buildRecentActivity(orders), hasLength(5));
    expect(buildRecentActivity(orders, limit: 2), hasLength(2));
  });

  test('zero-total order has no amount', () {
    final feed = buildRecentActivity([Order(createdAt: base)]);
    expect(feed.single.amount, isNull);
  });
}
