class ProposedWorkItem {
  const ProposedWorkItem({
    required this.kind,
    required this.customerId,
    required this.customerName,
    required this.draftMessage,
    required this.priority,
  });

  final String kind;
  final String customerId;
  final String customerName;
  final String draftMessage;
  final String priority;

  factory ProposedWorkItem.fromMap(Map<String, dynamic> map) => ProposedWorkItem(
        kind: map['kind']?.toString() ?? '',
        customerId: map['customer_id']?.toString() ?? '',
        customerName: map['customer_name']?.toString() ?? '',
        draftMessage: map['draft_message']?.toString() ?? '',
        priority: map['priority']?.toString() ?? 'medium',
      );

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'customer_id': customerId,
        'customer_name': customerName,
        'draft_message': draftMessage,
        'priority': priority,
      };
}

class AssistantResponse {
  const AssistantResponse({
    required this.answer,
    required this.suggestions,
    required this.proposedWorkItems,
  });

  final String answer;
  final List<String> suggestions;
  final List<ProposedWorkItem> proposedWorkItems;

  factory AssistantResponse.fromMap(Map<String, dynamic> map) {
    final suggestionsRaw = map['suggestions'] as List? ?? const [];
    final itemsRaw = map['proposed_work_items'] as List? ?? const [];
    return AssistantResponse(
      answer: map['answer']?.toString() ?? '',
      suggestions: [for (final s in suggestionsRaw) s.toString()],
      proposedWorkItems: [
        for (final i in itemsRaw)
          if (i is Map) ProposedWorkItem.fromMap(Map<String, dynamic>.from(i)),
      ],
    );
  }
}

class AssistantTurn {
  const AssistantTurn._({
    required this.role,
    required this.text,
    required this.proposedItems,
  });

  final String role;
  final String text;
  final List<ProposedWorkItem> proposedItems;

  factory AssistantTurn.user(String text) => AssistantTurn._(
        role: 'user',
        text: text,
        proposedItems: const [],
      );

  factory AssistantTurn.assistant(
    String text, {
    List<ProposedWorkItem> proposedItems = const [],
  }) =>
      AssistantTurn._(
        role: 'assistant',
        text: text,
        proposedItems: proposedItems,
      );

  Map<String, dynamic> toHistoryMap() => {'role': role, 'content': text};
}
