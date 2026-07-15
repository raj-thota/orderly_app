import 'package:supabase_flutter/supabase_flutter.dart';

import 'assistant_message.dart';

abstract class AssistantService {
  Future<AssistantResponse> ask({
    required String question,
    String? customerId,
    List<Map<String, dynamic>> history,
  });

  Future<void> confirmWorkItem(ProposedWorkItem item);
}

class SupabaseAssistantService implements AssistantService {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<AssistantResponse> ask({
    required String question,
    String? customerId,
    List<Map<String, dynamic>> history = const [],
  }) async {
    final res = await _client.functions.invoke(
      'assistant',
      body: {
        'question': question,
        if (customerId != null) 'customer_id': customerId, // ignore: use_null_aware_elements
        'history': history,
      },
    );
    if (res.data == null) throw Exception('assistant_empty_response');
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return AssistantResponse.fromMap(data);
  }

  @override
  Future<void> confirmWorkItem(ProposedWorkItem item) async {
    await _client.from('ai_work_items').insert({
      'kind': item.kind,
      'customer_id': item.customerId,
      'draft_message': item.draftMessage,
      'priority': item.priority,
      'status': 'pending',
      'source': 'assistant',
    });
  }
}
