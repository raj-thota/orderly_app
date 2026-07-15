import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/conversations_service.dart' show ConversationsService, SupabaseConversationsService;
import '../data/customer_summary_service.dart' show CustomerSummaryService, SupabaseCustomerSummaryService;
import '../data/draft_reply_service.dart' show DraftReply, DraftReplyService, SupabaseDraftReplyService;
import '../data/message.dart';

// ─── Service providers ────────────────────────────────────────────────────────

final conversationsServiceProvider =
    Provider<ConversationsService>((_) => SupabaseConversationsService());

final customerSummaryServiceProvider =
    Provider<CustomerSummaryService>((_) => SupabaseCustomerSummaryService());

final draftReplyServiceProvider =
    Provider<DraftReplyService>((_) => SupabaseDraftReplyService());

// ─── State ────────────────────────────────────────────────────────────────────

class ConversationState {
  const ConversationState({
    this.messages = const [],
    this.draft,
    this.draftLoading = false,
    this.loading = false,
  });

  final List<Message> messages;
  final DraftReply? draft;
  final bool draftLoading;
  final bool loading;

  ConversationState copyWith({
    List<Message>? messages,
    DraftReply? Function()? draft,
    bool? draftLoading,
    bool? loading,
  }) {
    return ConversationState(
      messages: messages ?? this.messages,
      draft: draft != null ? draft() : this.draft,
      draftLoading: draftLoading ?? this.draftLoading,
      loading: loading ?? this.loading,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class ConversationNotifier extends StateNotifier<ConversationState> {
  ConversationNotifier(this._customerId, this._conv, this._draft)
      : super(const ConversationState());

  final String _customerId;
  final ConversationsService _conv;
  final DraftReplyService _draft;
  String? _conversationId;

  Future<void> load() => loadMessages(_customerId);

  Future<void> _ensureConversation(String customerId) async {
    if (_conversationId != null) return;
    final convo = await _conv.getOrCreate(customerId);
    _conversationId = convo.id;
  }

  Future<void> loadMessages(String customerId) async {
    state = state.copyWith(loading: true);
    await _ensureConversation(customerId);
    try {
      final msgs = await _conv.fetchMessages(_conversationId!);
      state = state.copyWith(messages: msgs, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> logAiSend(String customerId, String message) async {
    await _ensureConversation(customerId);
    final msg = await _conv.addMessage(
      conversationId: _conversationId!,
      direction: 'outbound',
      source: 'ai_send',
      body: message,
    );
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  Future<void> requestDraft(String customerId, {required String objective}) async {
    state = state.copyWith(draftLoading: true);
    final result = await _draft.generate(
      customerId: customerId,
      objective: objective,
    );
    state = state.copyWith(
      draftLoading: false,
      draft: () => result,
    );
  }

  void clearDraft() {
    state = state.copyWith(draft: () => null);
  }
}

// ─── Provider family ──────────────────────────────────────────────────────────

final conversationNotifierProvider = StateNotifierProvider.family
    .autoDispose<ConversationNotifier, ConversationState, String>(
  (ref, customerId) => ConversationNotifier(
    customerId,
    ref.watch(conversationsServiceProvider),
    ref.watch(draftReplyServiceProvider),
  ),
);
