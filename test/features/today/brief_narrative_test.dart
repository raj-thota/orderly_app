import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/today/data/brief_narrative.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _item({
  String id = '1',
  String kind = 'payment_reminder',
  String? customerName,
  double? amount,
}) =>
    AiWorkItem(
      id: id,
      kind: kind,
      priority: 'high',
      score: 90,
      title: 't',
      status: 'pending',
      batchId: 'b',
      customerName: customerName,
      amount: amount,
    );

final _morning = DateTime(2026, 7, 15, 9);
final _afternoon = DateTime(2026, 7, 15, 14);
final _evening = DateTime(2026, 7, 15, 19);

void main() {
  group('briefDaypart', () {
    test('boundaries', () {
      expect(briefDaypart(DateTime(2026, 1, 1, 11, 59)), BriefDaypart.morning);
      expect(briefDaypart(DateTime(2026, 1, 1, 12)), BriefDaypart.afternoon);
      expect(briefDaypart(DateTime(2026, 1, 1, 16, 59)), BriefDaypart.afternoon);
      expect(briefDaypart(DateTime(2026, 1, 1, 17)), BriefDaypart.evening);
    });
  });

  group('buildBriefNarrative', () {
    test('all clear in the morning', () {
      final n = buildBriefNarrative(
          brief: const TodayBrief(), items: const [], now: _morning);
      expect(n.eyebrow, 'YOUR MORNING BRIEF');
      expect(n.body, contains('All clear'));
    });

    test('evening wrap-up celebrates revenue when nothing is pending', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(revenueToday: 9500, ordersToday: 2),
        items: const [],
        now: _evening,
      );
      expect(n.eyebrow, 'YOUR EVENING BRIEF');
      expect(n.body, contains('₹9,500'));
      expect(n.body, contains('2 orders'));
    });

    test('counts collections and replies separately', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(),
        items: [
          _item(id: '1', amount: 1500),
          _item(id: '2', kind: 'overdue_payment', amount: 2000),
          _item(id: '3', kind: 'follow_up'),
        ],
        now: _morning,
      );
      expect(n.body, contains('3 things need you today.'));
      expect(n.body, contains('₹3,500 to collect from 2 customers'));
      expect(n.body, contains('1 customer is waiting on a reply'));
    });

    test('singular grammar for one pending reply', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(),
        items: [_item(kind: 'call')],
        now: _afternoon,
      );
      expect(n.eyebrow, 'YOUR AFTERNOON BRIEF');
      expect(n.body, contains('1 thing needs you today.'));
      expect(n.body, contains('1 customer is waiting on a reply'));
    });

    test('offer kinds are narrated, not silently dropped', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(),
        items: [
          _item(amount: 1200),
          _item(id: '2', kind: 'offer'),
        ],
        now: _morning,
      );
      expect(n.body, contains('2 things need you today.'));
      expect(n.body, contains('1 customer to win back with an offer'));
    });

    test('collect kinds without amounts fall back to plain wording', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(),
        items: [_item()],
        now: _morning,
      );
      expect(n.body, contains('Payments to collect from 1 customer'));
    });

    test('evening lead mentions open tasks plus revenue collected', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(revenueToday: 500),
        items: [_item(), _item(id: '2', kind: 'offer')],
        now: _evening,
      );
      expect(n.body, startsWith('You collected ₹500 today.'));
      expect(n.body, contains('2 tasks still open.'));
    });
  });

  group('brief bullets', () {
    test('one conversational bullet per action type, in fixed order', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(),
        items: [
          _item(id: '1', amount: 9957.50),
          _item(id: '2', kind: 'overdue_payment', amount: 2000),
          _item(id: '3', kind: 'follow_up'),
          _item(id: '4', kind: 'reply'),
          _item(id: '5', kind: 'offer'),
        ],
        now: _morning,
      );
      expect(n.bullets, [
        'Collect ₹11,957.50 from 2 customers',
        'Reply to 2 waiting customers',
        'Win back 1 inactive customer',
      ]);
    });

    test('singular wording for one of each', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(),
        items: [
          _item(id: '1', amount: 500),
          _item(id: '2', kind: 'follow_up'),
          _item(id: '3', kind: 'offer'),
        ],
        now: _afternoon,
      );
      expect(n.bullets, [
        'Collect ₹500 from 1 customer',
        'Reply to 1 waiting customer',
        'Win back 1 inactive customer',
      ]);
    });

    test('collect bullet without amounts falls back to plain wording', () {
      final n = buildBriefNarrative(
          brief: const TodayBrief(), items: [_item()], now: _morning);
      expect(n.bullets, ['Collect payments from 1 customer']);
    });

    test('unknown kinds get a catch-all bullet, not silently dropped', () {
      final n = buildBriefNarrative(
        brief: const TodayBrief(),
        items: [_item(amount: 500), _item(id: '2', kind: 'mystery')],
        now: _morning,
      );
      expect(n.bullets, [
        'Collect ₹500 from 1 customer',
        'Handle 1 other task',
      ]);
    });

    test('empty when nothing is pending', () {
      final allClear = buildBriefNarrative(
          brief: const TodayBrief(), items: const [], now: _morning);
      expect(allClear.bullets, isEmpty);

      final eveningWrap = buildBriefNarrative(
        brief: const TodayBrief(revenueToday: 9500),
        items: const [],
        now: _evening,
      );
      expect(eveningWrap.bullets, isEmpty);
    });
  });

  group('estimatedMinutes', () {
    test('per-kind estimates', () {
      expect(estimatedMinutesFor(_item()), 2); // collect
      expect(estimatedMinutesFor(_item(kind: 'follow_up')), 3); // reply
      expect(estimatedMinutesFor(_item(kind: 'offer')), 3);
      expect(estimatedMinutesFor(_item(kind: 'unknown')), 2);
    });

    test('sums across items and is zero when empty', () {
      expect(estimatedMinutes(const []), 0);
      expect(
        estimatedMinutes([_item(), _item(id: '2', kind: 'follow_up')]),
        5,
      );
    });
  });

  group('focusLabel', () {
    test('payment with amount', () {
      expect(focusLabel(_item(customerName: 'Priya', amount: 3360)),
          'Collect ₹3,360 from Priya');
    });

    test('payment without amount', () {
      expect(focusLabel(_item(customerName: 'Priya')),
          'Collect payment from Priya');
    });

    test('follow up, offer, and default kinds', () {
      expect(focusLabel(_item(kind: 'follow_up', customerName: 'Aman')),
          'Follow up with Aman');
      expect(focusLabel(_item(kind: 'offer', customerName: 'Aman')),
          'Send Aman an offer');
      expect(focusLabel(_item(kind: 'reply', customerName: 'Aman')),
          'Reply to Aman');
    });

    test('missing name falls back to "a customer"', () {
      expect(focusLabel(_item(kind: 'reply')), 'Reply to a customer');
    });
  });
}
