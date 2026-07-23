import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';

Subscription _sub({
  String status = 'trialing',
  DateTime? trialEnd,
  DateTime? currentPeriodEnd,
  String? gateway,
  String plan = 'pro_monthly',
}) =>
    Subscription(
      id: 's1',
      userId: 'u1',
      plan: plan,
      status: status,
      trialEnd: trialEnd,
      currentPeriodEnd: currentPeriodEnd,
      gateway: gateway,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('Subscription.fromMap', () {
    test('parses all fields', () {
      final s = Subscription.fromMap({
        'id': 's1',
        'user_id': 'u1',
        'plan': 'pro_monthly',
        'status': 'active',
        'gateway': 'razorpay',
        'gateway_customer_id': 'cust_1',
        'gateway_subscription_id': 'sub_1',
        'current_period_end': '2026-08-01T00:00:00Z',
        'trial_end': null,
        'created_at': '2026-07-01T00:00:00Z',
      });
      expect(s.status, 'active');
      expect(s.gateway, 'razorpay');
      expect(s.gatewaySubscriptionId, 'sub_1');
      expect(s.currentPeriodEnd, DateTime.utc(2026, 8, 1));
      expect(s.trialEnd, isNull);
    });

    test('tolerates nulls', () {
      final s = Subscription.fromMap({
        'id': 's2',
        'user_id': 'u1',
        'plan': 'pro_monthly',
        'status': 'trialing',
        'created_at': '2026-07-01T00:00:00Z',
      });
      expect(s.gateway, isNull);
      expect(s.currentPeriodEnd, isNull);
    });
  });

  group('entitlement', () {
    test('trialing with future trial_end → EntitlementStatus.trialing', () {
      final s = _sub(
        status: 'trialing',
        trialEnd: DateTime.now().add(const Duration(days: 7)),
      );
      expect(s.entitlement, EntitlementStatus.trialing);
    });

    test('trialing with past trial_end → EntitlementStatus.gated', () {
      final s = _sub(
        status: 'trialing',
        trialEnd: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(s.entitlement, EntitlementStatus.gated);
    });

    test('trialing with null trial_end → EntitlementStatus.gated', () {
      final s = _sub(status: 'trialing', trialEnd: null);
      expect(s.entitlement, EntitlementStatus.gated);
    });

    test('active → EntitlementStatus.active', () {
      final s = _sub(
        status: 'active',
        currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
        gateway: 'razorpay',
      );
      expect(s.entitlement, EntitlementStatus.active);
    });

    test('past_due → EntitlementStatus.gated', () {
      expect(_sub(status: 'past_due').entitlement, EntitlementStatus.gated);
    });

    test('cancelled → EntitlementStatus.gated', () {
      expect(_sub(status: 'cancelled').entitlement, EntitlementStatus.gated);
    });

    test('expired → EntitlementStatus.gated', () {
      expect(_sub(status: 'expired').entitlement, EntitlementStatus.gated);
    });
  });

  group('hasAiAccess', () {
    test('valid trial and active Pro both unlock AI', () {
      final trialing = _sub(
          status: 'trialing',
          trialEnd: DateTime.now().add(const Duration(days: 5)));
      final active = _sub(status: 'active', gateway: 'razorpay');
      expect(trialing.hasAiAccess, isTrue);
      expect(active.hasAiAccess, isTrue);
    });

    test('gated statuses lock AI', () {
      expect(_sub(status: 'expired').hasAiAccess, isFalse);
      expect(_sub(status: 'cancelled').hasAiAccess, isFalse);
      expect(
          _sub(
                  status: 'trialing',
                  trialEnd: DateTime.now().subtract(const Duration(days: 1)))
              .hasAiAccess,
          isFalse);
    });

    test('an active non-AI plan does not unlock AI', () {
      expect(
          _sub(status: 'active', plan: 'starter_monthly').hasAiAccess, isFalse);
    });
  });

  group('trialDaysLeft', () {
    test('rounds up and never reports 0 while the trial is valid', () {
      expect(
          _sub(trialEnd: DateTime.now().add(const Duration(days: 6, hours: 2)))
              .trialDaysLeft,
          7);
      expect(
          _sub(trialEnd: DateTime.now().add(const Duration(minutes: 30)))
              .trialDaysLeft,
          1);
    });

    test('is 0 when expired or not trialing', () {
      expect(
          _sub(trialEnd: DateTime.now().subtract(const Duration(days: 1)))
              .trialDaysLeft,
          0);
      expect(_sub(status: 'active').trialDaysLeft, 0);
    });
  });
}
