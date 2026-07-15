class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.direction,
    required this.source,
    required this.body,
    this.userId,
    this.sentAt,
    this.meta = const {},
    this.createdAt,
  });

  final String id;
  final String conversationId;
  final String direction;
  final String source;
  final String body;
  final String? userId;
  final DateTime? sentAt;
  final Map<String, dynamic> meta;
  final DateTime? createdAt;

  bool get isInbound => direction == 'inbound';
  bool get isOutbound => direction == 'outbound';
  bool get isAiSend => source == 'ai_send';

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id']?.toString() ?? '',
      conversationId: map['conversation_id']?.toString() ?? '',
      direction: map['direction']?.toString() ?? 'inbound',
      source: map['source']?.toString() ?? 'manual',
      body: map['body']?.toString() ?? '',
      userId: map['user_id']?.toString(),
      sentAt: _parseDate(map['sent_at']),
      meta: (map['meta'] as Map<String, dynamic>?) ?? {},
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
