import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/customers/data/customer_stats.dart';

void main() {
  group('AiFact', () {
    test('fromMap parses fact and sourceMessageId', () {
      final f = AiFact.fromMap(
          {'fact': 'Prefers evening replies', 'source_message_id': 'msg-1'});
      expect(f.fact, 'Prefers evening replies');
      expect(f.sourceMessageId, 'msg-1');
    });

    test('fromMap tolerates missing sourceMessageId', () {
      final f = AiFact.fromMap({'fact': 'Repeat buyer'});
      expect(f.fact, 'Repeat buyer');
      expect(f.sourceMessageId, isNull);
    });
  });

  group('CustomerStats.fromMaps', () {
    test('parses stats and customer fields', () {
      final stats = CustomerStats.fromMaps(
        statsMap: {
          'customer_id': 'c1',
          'total_orders': 3,
          'lifetime_value': 15000.0,
          'outstanding': 2000.0,
        },
        customerMap: {
          'id': 'c1',
          'name': 'Priya',
          'phone': '9876543210',
          'ai_facts': [
            {'fact': 'Prefers evening', 'source_message_id': 'm1'},
          ],
          'last_contact_at': '2026-07-10T10:00:00Z',
        },
      );
      expect(stats.customerId, 'c1');
      expect(stats.totalOrders, 3);
      expect(stats.lifetimeValue, 15000.0);
      expect(stats.outstanding, 2000.0);
      expect(stats.name, 'Priya');
      expect(stats.phone, '9876543210');
      expect(stats.aiFacts, hasLength(1));
      expect(stats.aiFacts.first.fact, 'Prefers evening');
      expect(stats.lastContactAt, isNotNull);
    });

    test('tolerates null / missing fields', () {
      final stats = CustomerStats.fromMaps(
        statsMap: {'customer_id': 'c2', 'total_orders': 0},
        customerMap: {'id': 'c2', 'name': 'Rahul'},
      );
      expect(stats.lifetimeValue, 0.0);
      expect(stats.outstanding, 0.0);
      expect(stats.aiFacts, isEmpty);
      expect(stats.lastContactAt, isNull);
    });
  });

  group('relationshipScore', () {
    CustomerStats makeStats({
      int orders = 0,
      double ltv = 0,
      double outstanding = 0,
      DateTime? lastContact,
    }) =>
        CustomerStats(
          customerId: 'c1',
          name: 'Test',
          totalOrders: orders,
          lifetimeValue: ltv,
          outstanding: outstanding,
          lastContactAt: lastContact,
        );

    test('returns 0 for brand-new customer with no history', () {
      final score = makeStats().relationshipScore;
      expect(score, 0.0);
    });

    test('returns high score for loyal, recently-active, fully-paid customer', () {
      final score = makeStats(
        orders: 10,
        ltv: 50000,
        outstanding: 0,
        lastContact: DateTime.now().subtract(const Duration(days: 5)),
      ).relationshipScore;
      expect(score, greaterThanOrEqualTo(4.5));
    });

    test('score is lower when customer has old last contact', () {
      final recent = makeStats(
        orders: 3,
        ltv: 10000,
        outstanding: 0,
        lastContact: DateTime.now().subtract(const Duration(days: 7)),
      ).relationshipScore;
      final stale = makeStats(
        orders: 3,
        ltv: 10000,
        outstanding: 0,
        lastContact: DateTime.now().subtract(const Duration(days: 120)),
      ).relationshipScore;
      expect(recent, greaterThan(stale));
    });

    test('score is clamped to 0..5', () {
      final score = makeStats(orders: 100, ltv: 1000000, outstanding: 0,
              lastContact: DateTime.now())
          .relationshipScore;
      expect(score, lessThanOrEqualTo(5.0));
      expect(score, greaterThanOrEqualTo(0.0));
    });

    test('repeat buyer earns extra point over first-time buyer', () {
      final first = makeStats(orders: 1, ltv: 5000).relationshipScore;
      final repeat = makeStats(orders: 2, ltv: 10000).relationshipScore;
      expect(repeat, greaterThan(first));
    });
  });
}
