import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/orders/data/order.dart';

/// DB-only numbers for the Today brief card (M0: no AI involved).
/// Pure so it can be unit-tested without Supabase.
class TodayBrief {
  const TodayBrief({
    this.outstanding = 0,
    this.outstandingCount = 0,
    this.dueFollowUps = 0,
    this.dueName,
    this.dueSince,
    this.ordersToday = 0,
    this.revenueToday = 0,
  });

  final double outstanding;

  /// How many orders still have dues (for "across N orders" copy).
  final int outstandingCount;

  final int dueFollowUps;

  /// Customer name of the longest-waiting due follow-up, if known.
  final String? dueName;

  /// When that follow-up became due (for "waiting 8 hours" copy).
  final DateTime? dueSince;

  final int ordersToday;
  final double revenueToday;
}

TodayBrief buildTodayBrief({
  required List<Order> orders,
  required List<Enquiry> enquiries,
  required DateTime now,
}) {
  bool sameDay(DateTime? d) =>
      d != null && d.year == now.year && d.month == now.month && d.day == now.day;

  var outstanding = 0.0;
  var outstandingCount = 0;
  var ordersToday = 0;
  var revenueToday = 0.0;
  for (final o in orders) {
    // Cancelled orders owe nothing and need no confirmation; payments already
    // received on them are still real revenue.
    final cancelled = o.status == 'cancelled';
    if (!cancelled) {
      outstanding += o.dues;
      if (o.dues > 0) outstandingCount++;
      if (sameDay(o.createdAt)) ordersToday++;
    }
    for (final p in o.payments) {
      if (sameDay(p.paidAt)) revenueToday += p.amount;
    }
  }

  var dueFollowUps = 0;
  String? dueName;
  DateTime? dueSince;
  for (final e in enquiries) {
    final bucket = e.bucket(now);
    if (bucket != EnquiryBucket.overdue && bucket != EnquiryBucket.today) {
      continue;
    }
    dueFollowUps++;
    final due = e.followUpDate;
    if (due != null && (dueSince == null || due.isBefore(dueSince))) {
      dueSince = due;
      dueName = e.customerName;
    }
  }

  return TodayBrief(
    // Paise-round accumulated money so float drift can't reach the UI.
    outstanding: (outstanding * 100).round() / 100,
    outstandingCount: outstandingCount,
    dueFollowUps: dueFollowUps,
    dueName: dueName,
    dueSince: dueSince,
    ordersToday: ordersToday,
    revenueToday: (revenueToday * 100).round() / 100,
  );
}
