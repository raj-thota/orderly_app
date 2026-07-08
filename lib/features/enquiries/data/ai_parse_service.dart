import 'package:supabase_flutter/supabase_flutter.dart';

import 'capture_draft.dart';

/// AI-refined fields. A null field means the model did not provide a value
/// (so the rules result should stand for that field); an empty [items] list
/// is distinct from a null [items].
class AiParse {
  const AiParse({
    this.name,
    this.phone,
    this.items,
    this.intent,
    this.type,
    this.followUpDate,
    this.confidence = 0,
  });

  final String? name;
  final String? phone;
  final List<DraftItem>? items;
  final String? intent;
  final String? type;
  final DateTime? followUpDate;
  final double confidence;
}

/// Sends text to the `parse-enquiry` edge function and coerces the untrusted
/// JSON into a strict [AiParse]. Never throws and never blocks longer than
/// [timeout]; any failure resolves to null so the caller keeps the rules draft.
typedef AiInvoker = Future<Map<String, dynamic>?> Function(String text);

class AiParseService {
  AiParseService({
    AiInvoker? invoker,
    Duration timeout = const Duration(seconds: 3),
  })  : _invoke = invoker ?? _defaultInvoke,
        _timeout = timeout;

  final AiInvoker _invoke;
  final Duration _timeout;

  static const _intents = {'inquiry', 'order', 'follow_up'};
  static const _types = {'enquiry', 'order'};

  static Future<Map<String, dynamic>?> _defaultInvoke(String text) async {
    final res = await Supabase.instance.client.functions
        .invoke('parse-enquiry', body: {'text': text});
    final data = res.data;
    return data is Map<String, dynamic> ? data : null;
  }

  Future<AiParse?> refine(String text) async {
    try {
      final json = await _invoke(text).timeout(_timeout);
      if (json == null) return null;
      return _coerce(json);
    } catch (_) {
      return null;
    }
  }

  AiParse _coerce(Map<String, dynamic> j) {
    String? cleanName(dynamic v) {
      final s = (v is String) ? v.trim() : '';
      return s.isEmpty ? null : s;
    }

    List<DraftItem>? cleanItems(dynamic v) {
      if (v is! List) return null;
      final out = <DraftItem>[];
      for (final e in v) {
        if (e is! Map) continue;
        final name = (e['name'] is String) ? (e['name'] as String).trim() : '';
        if (name.isEmpty) continue;
        final qtyRaw = e['qty'];
        final qty = (qtyRaw is num) ? qtyRaw.toInt() : 1;
        final priceRaw = e['price'];
        final price = (priceRaw is num) ? priceRaw.toDouble() : null;
        out.add(DraftItem(name: name, qty: qty < 1 ? 1 : qty, price: price));
      }
      return out;
    }

    String? whitelist(dynamic v, Set<String> allowed) {
      return (v is String && allowed.contains(v)) ? v : null;
    }

    // Match the rules parser's strict shape; the coercion layer is the trust
    // boundary, so a malformed AI phone must not seed a bad customer identity.
    String? cleanPhone(dynamic v) {
      final normalized =
          CaptureDraft.normalizePhone(v is String ? v : null);
      if (normalized == null) return null;
      return RegExp(r'^[6-9]\d{9}$').hasMatch(normalized) ? normalized : null;
    }

    DateTime? cleanDate(dynamic v) {
      if (v is! String) return null;
      final parsed = DateTime.tryParse(v);
      if (parsed == null) return null;
      // Drop past dates: a reminder scheduled in the past would never fire.
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      return parsed.isBefore(startOfToday) ? null : parsed;
    }

    double clampConfidence(dynamic v) {
      final d = (v is num) ? v.toDouble() : 0.0;
      if (d < 0) return 0;
      if (d > 1) return 1;
      return d;
    }

    return AiParse(
      name: cleanName(j['customer_name']),
      phone: cleanPhone(j['phone']),
      items: cleanItems(j['items']),
      intent: whitelist(j['intent'], _intents),
      type: whitelist(j['type'], _types),
      followUpDate: cleanDate(j['follow_up_date']),
      confidence: clampConfidence(j['confidence']),
    );
  }
}
