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

  bool get isAiUnlocked => entitlement != EntitlementStatus.gated;

  factory Subscription.fromMap(Map<String, dynamic> map) => Subscription(
        id: map['id']?.toString() ?? '',
        userId: map['user_id']?.toString() ?? '',
        plan: map['plan']?.toString() ?? 'pro_monthly',
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
