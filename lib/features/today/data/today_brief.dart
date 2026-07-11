import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/orders/data/order.dart';

/// DB-only numbers for the Today brief card (M0: no AI involved).
/// Pure so it can be unit-tested without Supabase.
class TodayBrief {
  const TodayBrief({
    this.outstanding = 0,
    this.dueFollowUps = 0,
    this.ordersToday = 0,
    this.revenueToday = 0,
  });

  final double outstanding;
  final int dueFollowUps;
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
  var ordersToday = 0;
  var revenueToday = 0.0;
  for (final o in orders) {
    outstanding += o.dues;
    if (sameDay(o.createdAt)) ordersToday++;
    for (final p in o.payments) {
      if (sameDay(p.paidAt)) revenueToday += p.amount;
    }
  }

  final dueFollowUps = enquiries.where((e) {
    final bucket = e.bucket(now);
    return bucket == EnquiryBucket.overdue || bucket == EnquiryBucket.today;
  }).length;

  return TodayBrief(
    outstanding: outstanding,
    dueFollowUps: dueFollowUps,
    ordersToday: ordersToday,
    revenueToday: revenueToday,
  );
}
