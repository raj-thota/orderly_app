import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';

/// Which risk/opportunity an insight card highlights.
enum HomeInsightKind { collectPayments, followUpsDue, newOrders }

/// An action-first AI-insight card: what to do, the evidence, and a CTA.
/// Pure data so derivation can be unit-tested; the widget layer decides
/// icons and colors per [kind].
class HomeInsight {
  const HomeInsight({
    required this.kind,
    required this.title,
    required this.evidence,
    required this.cta,
    required this.targetTab,
  });

  final HomeInsightKind kind;

  /// The action, phrased as a verb ("Collect outstanding payments").
  final String title;

  /// Why now — the numbers or the person behind the action.
  final String evidence;

  /// Short CTA label; the widget renders the arrow.
  final String cta;

  /// Bottom-nav tab to open on tap (1 = My Work, 2 = Orders).
  final int targetTab;
}

String _waitingSince(DateTime since, DateTime now) {
  final diff = now.difference(since);
  if (diff.inDays >= 1) {
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
  }
  if (diff.inHours >= 1) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'}';
  }
  return 'a little while';
}

/// Derives insight cards from the day's numbers, highest risk first.
List<HomeInsight> buildHomeInsights(TodayBrief brief, {required DateTime now}) {
  final insights = <HomeInsight>[];

  if (brief.outstanding > 0) {
    final orders = brief.outstandingCount > 0
        ? ' across ${brief.outstandingCount} order${brief.outstandingCount == 1 ? '' : 's'}'
        : '';
    insights.add(HomeInsight(
      kind: HomeInsightKind.collectPayments,
      title: 'Collect outstanding payments',
      evidence: '${Money.inr(brief.outstanding)} is pending$orders.',
      cta: 'Send reminders',
      targetTab: 2,
    ));
  }
  if (brief.dueFollowUps > 0) {
    final name = brief.dueName;
    final String evidence;
    if (name == null) {
      evidence =
          '${brief.dueFollowUps} customer${brief.dueFollowUps == 1 ? ' is' : 's are'} waiting on a reply.';
    } else if (brief.dueFollowUps == 1) {
      final since = brief.dueSince;
      if (since == null) {
        evidence = '$name is waiting on you.';
      } else if (since.isAfter(now)) {
        // Due later today — nobody is "waiting" yet.
        evidence = '$name is due for a follow-up today.';
      } else {
        evidence = '$name has been waiting ${_waitingSince(since, now)}.';
      }
    } else {
      evidence =
          '$name and ${brief.dueFollowUps - 1} other${brief.dueFollowUps == 2 ? '' : 's'} are waiting on replies.';
    }
    insights.add(HomeInsight(
      kind: HomeInsightKind.followUpsDue,
      title: brief.dueFollowUps == 1
          ? 'Reply to an interested customer'
          : 'Reply to interested customers',
      evidence: evidence,
      cta: 'Reply now',
      targetTab: 1,
    ));
  }
  if (brief.ordersToday > 0) {
    insights.add(HomeInsight(
      kind: HomeInsightKind.newOrders,
      title: "Confirm today's new orders",
      evidence:
          '${brief.ordersToday} order${brief.ordersToday == 1 ? '' : 's'} came in today.',
      cta: 'Review orders',
      targetTab: 2,
    ));
  }

  return insights;
}
