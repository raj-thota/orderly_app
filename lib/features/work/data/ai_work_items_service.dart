import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_work_item.dart';

abstract class AiWorkItemsService {
  Future<List<AiWorkItem>> fetchPending();
  Future<void> updateStatus(String id, String status);
  Future<void> approve(String id);
  Future<void> dismiss(String id);
  Future<void> markDone(String id);
  Future<void> triggerGenerate();
}

class SupabaseAiWorkItemsService implements AiWorkItemsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  static const _selectWithJoins = '*, customers(name)';

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
}
