enum EntitlementStatus { trialing, active, gated }

class Subscription {
  const Subscription({
    required this.id,
    required this.userId,
    required this.plan,
    required this.status,
    this.gateway,
    this.gatewayCustomerId,
    this.gatewaySubscriptionId,
    this.currentPeriodEnd,
    this.trialEnd,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String plan;
  final String status;
  final String? gateway;
  final String? gatewayCustomerId;
  final String? gatewaySubscriptionId;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEnd;
  final DateTime createdAt;

  EntitlementStatus get entitlement {
    switch (status) {
      case 'active':
        return EntitlementStatus.active;
      case 'trialing':
        if (trialEnd != null && trialEnd!.isAfter(DateTime.now())) {
          return EntitlementStatus.trialing;
        }
        return EntitlementStatus.gated;
      default:
        return EntitlementStatus.gated;
    }
  }

  static const _aiPlans = {'pro_monthly'};

  /// AI features (capture parse, assistant, drafts, summaries, work items)
  /// need a valid trial or an active subscription on an AI-bearing plan.
  /// Plan-aware so a future non-AI tier can't silently unlock AI. Mirrors the
  /// server-side check in supabase/functions/_shared/entitlement.ts.
  bool get hasAiAccess {
    switch (entitlement) {
      case EntitlementStatus.trialing:
      case EntitlementStatus.active:
        return _aiPlans.contains(plan);
      case EntitlementStatus.gated:
        return false;
    }
  }

  /// Days remaining in a valid trial (ceiling, minimum 1 while the trial is
  /// still running so copy never reads "0 days left"). 0 when not trialing.
  int get trialDaysLeft {
    if (entitlement != EntitlementStatus.trialing) return 0;
    final hours = trialEnd!.difference(DateTime.now()).inHours;
    return (hours / 24).ceil().clamp(1, 99);
  }

  factory Subscription.fromMap(Map<String, dynamic> map) => Subscription(
        id: map['id']?.toString() ?? '',
        userId: map['user_id']?.toString() ?? '',
        // Unknown plan must fail closed (no AI) — never default to an AI plan.
        plan: map['plan']?.toString() ?? '',
        status: map['status']?.toString() ?? 'expired',
        gateway: map['gateway']?.toString(),
        gatewayCustomerId: map['gateway_customer_id']?.toString(),
        gatewaySubscriptionId: map['gateway_subscription_id']?.toString(),
        currentPeriodEnd: DateTime.tryParse(
            map['current_period_end']?.toString() ?? ''),
        trialEnd:
            DateTime.tryParse(map['trial_end']?.toString() ?? ''),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}
