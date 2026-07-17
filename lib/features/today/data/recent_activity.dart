import 'package:orderly_app/features/orders/data/order.dart';

/// What happened: an order was created or a payment landed.
enum ActivityKind { orderCreated, paymentReceived }

/// One row in the Home "Recent activity" feed. Keeps a reference to the
/// source [order] so a tap can open its detail screen.
class ActivityEntry {
  const ActivityEntry({
    required this.kind,
    required this.at,
    required this.order,
    this.amount,
  });

  final ActivityKind kind;
  final DateTime at;
  final Order order;

  /// Payment amount for [ActivityKind.paymentReceived]; order total otherwise.
  final double? amount;
}

/// Flattens orders + their payments into a newest-first activity feed.
/// Entries without timestamps are skipped. Pure for unit testing.
List<ActivityEntry> buildRecentActivity(List<Order> orders, {int limit = 5}) {
  final entries = <ActivityEntry>[];

  for (final order in orders) {
    final createdAt = order.createdAt;
    if (createdAt != null) {
      entries.add(ActivityEntry(
        kind: ActivityKind.orderCreated,
        at: createdAt,
        order: order,
        amount: order.grandTotal > 0 ? order.grandTotal : null,
      ));
    }
    for (final payment in order.payments) {
      final paidAt = payment.paidAt;
      if (paidAt != null) {
        entries.add(ActivityEntry(
          kind: ActivityKind.paymentReceived,
          at: paidAt,
          order: order,
          amount: payment.amount,
        ));
      }
    }
  }

  entries.sort((a, b) => b.at.compareTo(a.at));
  return entries.take(limit).toList();
}
