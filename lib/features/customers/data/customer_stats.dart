/// A single AI-extracted fact about a customer.
class AiFact {
  const AiFact({required this.fact, this.sourceMessageId});

  final String fact;
  final String? sourceMessageId;

  factory AiFact.fromMap(Map<String, dynamic> map) => AiFact(
        fact: map['fact']?.toString() ?? '',
        sourceMessageId: map['source_message_id']?.toString(),
      );
}

/// Combined stats from the `customer_stats` view + full customer row.
class CustomerStats {
  const CustomerStats({
    required this.customerId,
    required this.name,
    required this.totalOrders,
    required this.lifetimeValue,
    required this.outstanding,
    this.phone,
    this.aiFacts = const [],
    this.birthday,
    this.lastContactAt,
  });

  final String customerId;
  final String name;
  final int totalOrders;
  final double lifetimeValue;
  final double outstanding;
  final String? phone;
  final List<AiFact> aiFacts;
  final DateTime? birthday;
  final DateTime? lastContactAt;

  /// Deterministic relationship score 0.0–5.0.
  ///
  /// Formula (documented for testability):
  ///   order_pts   = min(totalOrders / 5, 1.0) × 2.0   — up to 2 pts
  ///   repeat_pts  = totalOrders > 1 ? 1.0 : 0.0       — 1 pt for repeat buyer
  ///   payment_pts = lifetimeValue > 0
  ///                   ? (outstanding / lifetimeValue < 0.3 ? 1.0 : 0.3) : 0.0
  ///   recency_pts = daysSince < 30 ? 1.0
  ///                 : daysSince < 90 ? 0.5 : 0.0
  double get relationshipScore {
    final orderPts = (totalOrders / 5.0).clamp(0.0, 1.0) * 2.0;
    final repeatPts = totalOrders > 1 ? 1.0 : 0.0;
    final paymentPts = lifetimeValue > 0
        ? (outstanding / lifetimeValue < 0.3 ? 1.0 : 0.3)
        : 0.0;
    final daysSince = lastContactAt == null
        ? 999
        : DateTime.now().difference(lastContactAt!).inDays;
    final recencyPts =
        daysSince < 30 ? 1.0 : daysSince < 90 ? 0.5 : 0.0;
    return (orderPts + repeatPts + paymentPts + recencyPts).clamp(0.0, 5.0);
  }

  factory CustomerStats.fromMaps({
    required Map<String, dynamic> statsMap,
    required Map<String, dynamic> customerMap,
  }) {
    final factsRaw = customerMap['ai_facts'] as List? ?? const [];
    return CustomerStats(
      customerId:
          (statsMap['customer_id'] ?? customerMap['id'] ?? '').toString(),
      name: (customerMap['name'] ?? '').toString(),
      phone: customerMap['phone']?.toString(),
      totalOrders: int.tryParse(statsMap['total_orders']?.toString() ?? '') ?? 0,
      lifetimeValue:
          double.tryParse(statsMap['lifetime_value']?.toString() ?? '') ?? 0.0,
      outstanding:
          double.tryParse(statsMap['outstanding']?.toString() ?? '') ?? 0.0,
      aiFacts: [
        for (final f in factsRaw)
          if (f is Map) AiFact.fromMap(Map<String, dynamic>.from(f)),
      ],
      birthday: DateTime.tryParse(customerMap['birthday']?.toString() ?? ''),
      lastContactAt:
          DateTime.tryParse(customerMap['last_contact_at']?.toString() ?? ''),
    );
  }
}
