import 'package:supabase_flutter/supabase_flutter.dart';

import 'follow_up.dart';

class FollowUpsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  static const _selectWithJoins = '*, customers(name, phone)';

  Future<List<FollowUp>> fetchPending() async {
    final rows = await _client
        .from('follow_ups')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .eq('status', 'pending')
        .order('due_at', ascending: true);
    return rows.map<FollowUp>((r) => FollowUp.fromMap(r)).toList();
  }

  Future<List<FollowUp>> fetchForWeek(DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final rows = await _client
        .from('follow_ups')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .gte('due_at', weekStart.toUtc().toIso8601String())
        .lt('due_at', weekEnd.toUtc().toIso8601String())
        .order('due_at', ascending: true);
    return rows.map<FollowUp>((r) => FollowUp.fromMap(r)).toList();
  }

  Future<void> markDone(String id) async {
    await _client
        .from('follow_ups')
        .update({'status': 'done'})
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Future<void> markSkipped(String id) async {
    await _client
        .from('follow_ups')
        .update({'status': 'skipped'})
        .eq('id', id)
        .eq('user_id', _userId);
  }

  Future<FollowUp> upsertForLead({
    required String customerId,
    required String leadId,
    required DateTime dueAt,
    String kind = 'general',
    String? note,
  }) async {
    final userId = _userId;
    final row = await _client
        .from('follow_ups')
        .upsert(
          {
            'user_id': userId,
            'customer_id': customerId,
            'lead_id': leadId,
            'due_at': dueAt.toUtc().toIso8601String(),
            'kind': kind,
            'note': note,
            'status': 'pending',
          },
          onConflict: 'lead_id',
          ignoreDuplicates: false,
        )
        .select(_selectWithJoins)
        .single();
    return FollowUp.fromMap(row);
  }
}
