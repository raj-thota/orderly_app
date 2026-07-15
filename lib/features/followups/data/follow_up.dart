class FollowUp {
  const FollowUp({
    required this.id,
    required this.customerId,
    required this.dueAt,
    required this.kind,
    required this.status,
    this.userId,
    this.leadId,
    this.customerName,
    this.customerPhone,
    this.note,
    this.createdAt,
  });

  final String id;
  final String customerId;
  final DateTime dueAt;
  final String kind;
  final String status;
  final String? userId;
  final String? leadId;
  final String? customerName;
  final String? customerPhone;
  final String? note;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  bool isOverdue({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final startOfToday = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    );
    final localDueAt = dueAt.toLocal();
    return localDueAt.isBefore(startOfToday);
  }

  bool isDueToday({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final localDueAt = dueAt.toLocal();
    return localDueAt.year == currentTime.year &&
        localDueAt.month == currentTime.month &&
        localDueAt.day == currentTime.day;
  }

  /// Converts to the map format expected by NotificationService helpers
  /// during the transition from leads.follow_up_date to the follow_ups table.
  Map<String, dynamic> toNotificationMap() => {
    'id': id,
    'name': customerName ?? 'Customer',
    'follow_up_date': dueAt.toIso8601String(),
    'status': 'follow',
  };

  factory FollowUp.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'] as Map<String, dynamic>?;
    return FollowUp(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      dueAt: _parseDate(map['due_at']) ?? DateTime.now(),
      kind: map['kind']?.toString() ?? 'general',
      status: map['status']?.toString() ?? 'pending',
      userId: map['user_id']?.toString(),
      leadId: map['lead_id']?.toString(),
      customerName: customer?['name']?.toString(),
      customerPhone: customer?['phone']?.toString(),
      note: map['note']?.toString(),
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
