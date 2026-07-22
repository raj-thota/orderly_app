import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/assistant_message.dart';
import '../data/assistant_service.dart';

final assistantServiceProvider = Provider<AssistantService>(
  (_) => SupabaseAssistantService(),
);

class AssistantState {
  const AssistantState({
    this.turns = const [],
    this.thinking = false,
    this.error,
  });

  final List<AssistantTurn> turns;
  final bool thinking;
  final String? error;

  AssistantState copyWith({
    List<AssistantTurn>? turns,
    bool? thinking,
    String? error,
    bool clearError = false,
  }) =>
      AssistantState(
        turns: turns ?? this.turns,
        thinking: thinking ?? this.thinking,
        error: clearError ? null : (error ?? this.error),
      );
}

class AssistantChatNotifier extends StateNotifier<AssistantState> {
  AssistantChatNotifier(this._service) : super(const AssistantState());

  final AssistantService _service;

  Future<void> send(String question) async {
    final userTurn = AssistantTurn.user(question);
    final history = [
      for (final t in state.turns) t.toHistoryMap(),
    ];
    state = state.copyWith(
      turns: [...state.turns, userTurn],
      thinking: true,
      clearError: true,
    );
    try {
      final response = await _service.ask(
        question: question,
        history: history,
      );
      final assistantTurn = AssistantTurn.assistant(
        response.answer,
        proposedItems: response.proposedWorkItems,
      );
      state = state.copyWith(
        turns: [...state.turns, assistantTurn],
        thinking: false,
      );
    } catch (e) {
      debugPrint('assistant chat failed: $e');
      state = state.copyWith(
        thinking: false,
        error: "Closr AI couldn't respond. Please try again.",
      );
    }
  }

  Future<void> approveProposedItem(ProposedWorkItem item) async {
    await _service.confirmWorkItem(item);
    _removePendingItem(item);
  }

  void dismissProposedItem(ProposedWorkItem item) {
    _removePendingItem(item);
  }

  void _removePendingItem(ProposedWorkItem item) {
    state = state.copyWith(
      turns: [
        for (final t in state.turns)
          if (t.role == 'assistant' && t.proposedItems.contains(item))
            AssistantTurn.assistant(
              t.text,
              proposedItems: [
                for (final i in t.proposedItems)
                  if (i != item) i,
              ],
            )
          else
            t,
      ],
    );
  }
}

final assistantChatProvider = StateNotifierProvider.autoDispose<
    AssistantChatNotifier, AssistantState>((ref) {
  return AssistantChatNotifier(ref.watch(assistantServiceProvider));
});
