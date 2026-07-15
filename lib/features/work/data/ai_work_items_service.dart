import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_work_item.dart';

class AiWorkItemsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  static const _selectWithJoins = '*, customers(name)';

  Future<List<AiWorkItem>> fetchPending() async {
    final rows = await _client
        .from('ai_work_items')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .eq('status', 'pending')
        .order('score', ascending: false);
    return rows.map<AiWorkItem>((r) => AiWorkItem.fromMap(r)).toList();
  }

  Future<void> updateStatus(String id, String status) async {
    await _client
        .from('ai_work_items')
        .update({'status': status})
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Future<void> approve(String id) => updateStatus(id, 'approved');
  Future<void> dismiss(String id) => updateStatus(id, 'dismissed');
  Future<void> markDone(String id) => updateStatus(id, 'done');
}
