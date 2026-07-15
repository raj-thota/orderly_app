class AiSummary {
  const AiSummary({
    required this.id,
    required this.customerId,
    this.userId,
    this.bullets = const [],
    this.closeConfidence,
    this.sourceHash,
    this.createdAt,
  });

  final String id;
  final String customerId;
  final String? userId;
  final List<String> bullets;
  final double? closeConfidence;
  final String? sourceHash;
  final DateTime? createdAt;

  bool get hasSummary => bullets.isNotEmpty;

  factory AiSummary.fromMap(Map<String, dynamic> map) {
    List<String> parseBullets(dynamic v) {
      if (v is! List) return const [];
      return v.whereType<String>().toList();
    }

    double? parseConf(dynamic v) {
      if (v is! num) return null;
      final d = v.toDouble();
      if (d < 0) return 0;
      if (d > 1) return 1;
      return d;
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return AiSummary(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      userId: map['user_id']?.toString(),
      bullets: parseBullets(map['bullets']),
      closeConfidence: parseConf(map['close_confidence']),
      sourceHash: map['source_hash']?.toString(),
      createdAt: parseDate(map['created_at']),
    );
  }
}
