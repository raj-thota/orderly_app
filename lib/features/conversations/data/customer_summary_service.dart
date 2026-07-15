import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_summary.dart';

abstract class CustomerSummaryService {
  Future<AiSummary?> fetch(String customerId);
  Future<AiSummary?> refresh(String customerId);
}

typedef SummaryInvoker = Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> body);

class SupabaseCustomerSummaryService implements CustomerSummaryService {
  SupabaseCustomerSummaryService(
      {SummaryInvoker? invoker, SupabaseClient? client})
      : _invoke = invoker ?? _defaultInvoke,
        _client = client;

  final SummaryInvoker _invoke;
  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  static Future<Map<String, dynamic>?> _defaultInvoke(
      Map<String, dynamic> body) async {
    final res = await Supabase.instance.client.functions
        .invoke('summarize-customer', body: body);
    final data = res.data;
    return data is Map<String, dynamic> ? data : null;
  }

  @override
  Future<AiSummary?> fetch(String customerId) async {
    final row = await _db
        .from('ai_summaries')
        .select()
        .eq('user_id', _db.auth.currentUser!.id)
        .eq('customer_id', customerId)
        .maybeSingle();
    return row == null ? null : AiSummary.fromMap(row);
  }

  @override
  Future<AiSummary?> refresh(String customerId) async {
    try {
      final json = await _invoke({'customer_id': customerId})
          .timeout(const Duration(seconds: 12));
      if (json == null) return null;
      return await fetch(customerId);
    } catch (_) {
      return null;
    }
  }
}
