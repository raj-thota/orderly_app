import 'package:supabase_flutter/supabase_flutter.dart';

import 'conversation.dart';
import 'message.dart';

class ConversationsService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  Future<Conversation?> fetchByCustomerId(String customerId) async {
    final row = await _client
        .from('conversations')
        .select('*, customers(name, phone)')
        .eq('user_id', _userId)
        .eq('customer_id', customerId)
        .maybeSingle();
    return row == null ? null : Conversation.fromMap(row);
  }

  Future<List<Message>> fetchMessages(String conversationId) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('user_id', _userId)
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return rows.map<Message>((r) => Message.fromMap(r)).toList();
  }

  Future<Message> addMessage({
    required String conversationId,
    required String direction,
    required String source,
    required String body,
    DateTime? sentAt,
    Map<String, dynamic> meta = const {},
  }) async {
    final userId = _userId;
    final row = await _client
        .from('messages')
        .insert({
          'user_id': userId,
          'conversation_id': conversationId,
          'direction': direction,
          'source': source,
          'body': body,
          if (sentAt != null) 'sent_at': sentAt.toUtc().toIso8601String(),
          'meta': meta,
        })
        .select()
        .single();
    return Message.fromMap(row);
  }
}
