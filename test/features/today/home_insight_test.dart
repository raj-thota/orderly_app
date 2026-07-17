import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/today/data/home_insight.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';

void main() {
  final now = DateTime(2026, 7, 15, 18);

  test('empty brief yields no insights', () {
    expect(buildHomeInsights(const TodayBrief(), now: now), isEmpty);
  });

  test('all signals produce ordered action cards: collect, reply, confirm',
      () {
    final insights = buildHomeInsights(
      TodayBrief(
        outstanding: 42092,
        outstandingCount: 7,
        dueFollowUps: 1,
        dueName: 'Meera',
        dueSince: now.subtract(const Duration(hours: 8)),
        ordersToday: 2,
      ),
      now: now,
    );

    expect(insights, hasLength(3));

    expect(insights[0].kind, HomeInsightKind.collectPayments);
    expect(insights[0].title, 'Collect outstanding payments');
    expect(insights[0].evidence, '₹42,092 is pending across 7 orders.');
    expect(insights[0].cta, 'Send reminders');
    expect(insights[0].targetTab, 2);

    expect(insights[1].kind, HomeInsightKind.followUpsDue);
    expect(insights[1].title, 'Reply to an interested customer');
    expect(insights[1].evidence, 'Meera has been waiting 8 hours.');
    expect(insights[1].cta, 'Reply now');
    expect(insights[1].targetTab, 1);

    expect(insights[2].kind, HomeInsightKind.newOrders);
    expect(insights[2].title, "Confirm today's new orders");
    expect(insights[2].evidence, '2 orders came in today.');
    expect(insights[2].cta, 'Review orders');
    expect(insights[2].targetTab, 2);
  });

  test('waiting time humanizes days and short waits', () {
    final dayWait = buildHomeInsights(
      TodayBrief(
        dueFollowUps: 1,
        dueName: 'Meera',
        dueSince: now.subtract(const Duration(days: 2)),
      ),
      now: now,
    );
    expect(dayWait.single.evidence, 'Meera has been waiting 2 days.');

    final shortWait = buildHomeInsights(
      TodayBrief(
        dueFollowUps: 1,
        dueName: 'Meera',
        dueSince: now.subtract(const Duration(minutes: 20)),
      ),
      now: now,
    );
    expect(shortWait.single.evidence, 'Meera has been waiting a little while.');
  });

  test('follow-up due later today is not called "waiting"', () {
    final insights = buildHomeInsights(
      TodayBrief(
        dueFollowUps: 1,
        dueName: 'Meera',
        dueSince: now.add(const Duration(hours: 3)),
      ),
      now: now,
    );

    expect(insights.single.evidence, 'Meera is due for a follow-up today.');
  });

  test('multiple follow-ups name the longest-waiting customer', () {
    final insights = buildHomeInsights(
      TodayBrief(
        dueFollowUps: 3,
        dueName: 'Meera',
        dueSince: now.subtract(const Duration(hours: 8)),
      ),
      now: now,
    );

    expect(insights.single.title, 'Reply to interested customers');
    expect(insights.single.evidence,
        'Meera and 2 others are waiting on replies.');
  });

  test('follow-ups without a known name fall back to counts', () {
    final insights = buildHomeInsights(
      const TodayBrief(dueFollowUps: 2),
      now: now,
    );

    expect(
        insights.single.evidence, '2 customers are waiting on a reply.');
  });

  test('singular grammar', () {
    final insights = buildHomeInsights(
      const TodayBrief(outstanding: 500, outstandingCount: 1, ordersToday: 1),
      now: now,
    );

    expect(insights[0].evidence, '₹500 is pending across 1 order.');
    expect(insights[1].evidence, '1 order came in today.');
  });
}
