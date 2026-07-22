import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_work_item.dart';

abstract class AiWorkItemsService {
  Future<List<AiWorkItem>> fetchPending();
  Future<void> updateStatus(String id, String status);
  Future<void> approve(String id);
  Future<void> dismiss(String id);
  Future<void> markDone(String id);
  Future<void> triggerGenerate();

  /// Inserts a pending work item that mirrors a just-captured lead/order, so
  /// what the user adds via the "Add to my work" flow shows up in My Work
  /// immediately (the AI batch generator only backfills it later).
  Future<void> createFromCapture({
    required String kind,
    required String priority,
    required int score,
    required String title,
    String? customerId,
    String? leadId,
    String? orderId,
    String? context,
    double? amount,
    double? confidence,
  });
}

class SupabaseAiWorkItemsService implements AiWorkItemsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  static const _selectWithJoins = '*, customers(name, phone)';

  @override
  Future<List<AiWorkItem>> fetchPending() async {
    final rows = await _client
        .from('ai_work_items')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .eq('status', 'pending')
        .order('score', ascending: false);
    return rows.map<AiWorkItem>((r) => AiWorkItem.fromMap(r)).toList();
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    await _client
        .from('ai_work_items')
        .update({'status': status})
        .eq('id', id)
        .eq('user_id', _userId);
  }

  @override
  Future<void> approve(String id) => updateStatus(id, 'approved');

  @override
  Future<void> dismiss(String id) => updateStatus(id, 'dismissed');

  @override
  Future<void> markDone(String id) => updateStatus(id, 'done');

  @override
  Future<void> triggerGenerate() async {
    await _client.functions.invoke('generate-work-items', body: {});
  }

  @override
  Future<void> createFromCapture({
    required String kind,
    required String priority,
    required int score,
    required String title,
    String? customerId,
    String? leadId,
    String? orderId,
    String? context,
    double? amount,
    double? confidence,
  }) async {
    // batch_id is NOT NULL with no default; reuse the source record's id (a
    // uuid, unique per capture) so a manual add is its own single-item batch.
    final batchId = leadId ?? orderId;
    if (batchId == null) return; // nothing to link to; skip rather than fail
    await _client.from('ai_work_items').insert({
      'user_id': _userId,
      'kind': kind,
      'priority': priority,
      'score': score,
      'title': title,
      'batch_id': batchId,
      'status': 'pending',
      'customer_id': ?customerId,
      'lead_id': ?leadId,
      'order_id': ?orderId,
      if (context != null && context.isNotEmpty) 'context': context,
      'amount': ?amount,
      'confidence': ?confidence,
    });
  }
}
