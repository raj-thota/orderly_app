import 'package:supabase_flutter/supabase_flutter.dart';

class DraftReply {
  const DraftReply({required this.message, required this.confidence});
  final String message;
  final double confidence;
}

abstract class DraftReplyService {
  Future<DraftReply?> generate({
    required String customerId,
    required String objective,
  });
}

typedef DraftReplyInvoker = Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> body);

class SupabaseDraftReplyService implements DraftReplyService {
  SupabaseDraftReplyService({
    DraftReplyInvoker? invoker,
    Duration timeout = const Duration(seconds: 6),
  })  : _invoke = invoker ?? _defaultInvoke,
        _timeout = timeout;

  final DraftReplyInvoker _invoke;
  final Duration _timeout;

  static Future<Map<String, dynamic>?> _defaultInvoke(
      Map<String, dynamic> body) async {
    final res = await Supabase.instance.client.functions
        .invoke('draft-reply', body: body);
    final data = res.data;
    return data is Map<String, dynamic> ? data : null;
  }

  @override
  Future<DraftReply?> generate({
    required String customerId,
    required String objective,
  }) async {
    try {
      final json = await _invoke({
        'customer_id': customerId,
        'objective': objective,
      }).timeout(_timeout);
      if (json == null) return null;
      return _coerce(json);
    } catch (_) {
      return null;
    }
  }

  DraftReply? _coerce(Map<String, dynamic> j) {
    final raw = j['message'];
    final msg = (raw is String) ? raw.trim() : '';
    if (msg.isEmpty) return null;

    final confRaw = j['confidence'];
    double conf = (confRaw is num) ? confRaw.toDouble() : 0.0;
    if (conf < 0) conf = 0;
    if (conf > 1) conf = 1;

    return DraftReply(message: msg, confidence: conf);
  }
}
