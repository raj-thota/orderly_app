class AiWorkItem {
  const AiWorkItem({
    required this.id,
    required this.kind,
    required this.priority,
    required this.score,
    required this.title,
    required this.status,
    required this.batchId,
    this.userId,
    this.customerId,
    this.customerName,
    this.phone,
    this.leadId,
    this.orderId,
    this.context,
    this.amount,
    this.draftMessage,
    this.confidence,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String kind;
  final String priority;
  final int score;
  final String title;
  final String status;
  final String batchId;
  final String? userId;
  final String? customerId;
  final String? customerName;
  final String? phone;
  final String? leadId;
  final String? orderId;
  final String? context;
  final double? amount;
  final String? draftMessage;
  final double? confidence;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';
  bool get isHigh => priority == 'high';
  bool get isMedium => priority == 'medium';
  bool get isLow => priority == 'low';

  factory AiWorkItem.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'] as Map<String, dynamic>?;
    final draft = map['draft'] as Map<String, dynamic>?;
    return AiWorkItem(
      id: map['id']?.toString() ?? '',
      kind: map['kind']?.toString() ?? '',
      priority: map['priority']?.toString() ?? 'low',
      score: int.tryParse(map['score']?.toString() ?? '') ?? 0,
      title: map['title']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      batchId: map['batch_id']?.toString() ?? '',
      userId: map['user_id']?.toString(),
      customerId: map['customer_id']?.toString(),
      customerName: customer?['name']?.toString(),
      phone: customer?['phone']?.toString(),
      leadId: map['lead_id']?.toString(),
      orderId: map['order_id']?.toString(),
      context: map['context']?.toString(),
      amount: _parseDouble(map['amount']),
      draftMessage: draft?['message']?.toString(),
      confidence: _parseDouble(map['confidence']),
      expiresAt: _parseDate(map['expires_at']),
      createdAt: _parseDate(map['created_at']),
    );
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
