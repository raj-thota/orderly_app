class Conversation {
  const Conversation({
    required this.id,
    required this.customerId,
    this.userId,
    this.customerName,
    this.customerPhone,
    this.lastMessageAt,
    this.createdAt,
  });

  final String id;
  final String customerId;
  final String? userId;
  final String? customerName;
  final String? customerPhone;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;

  factory Conversation.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'] as Map<String, dynamic>?;
    return Conversation(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      userId: map['user_id']?.toString(),
      customerName: customer?['name']?.toString(),
      customerPhone: customer?['phone']?.toString(),
      lastMessageAt: _parseDate(map['last_message_at']),
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
