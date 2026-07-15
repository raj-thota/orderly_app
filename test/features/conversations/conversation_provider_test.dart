import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/conversations/controller/conversation_provider.dart';
import 'package:orderly_app/features/conversations/data/ai_summary.dart';
import 'package:orderly_app/features/conversations/data/conversation.dart';
import 'package:orderly_app/features/conversations/data/conversations_service.dart';
import 'package:orderly_app/features/conversations/data/customer_summary_service.dart';
import 'package:orderly_app/features/conversations/data/draft_reply_service.dart';
import 'package:orderly_app/features/conversations/data/message.dart';

// ─── Fakes ───────────────────────────────────────────────────────────────────

class FakeConvService implements ConversationsService {
  final String _convId;
  List<Map<String, dynamic>> addedMessages = [];

  FakeConvService([this._convId = 'conv-1']);

  @override
  Future<Conversation> getOrCreate(String customerId) async =>
      Conversation(id: _convId, customerId: customerId);

  @override
  Future<Conversation?> fetchByCustomerId(String customerId) async =>
      Conversation(id: _convId, customerId: customerId);

  @override
  Future<List<Message>> fetchMessages(String conversationId) async => [
        Message(
          id: 'm-1',
          conversationId: conversationId,
          direction: 'inbound',
          source: 'paste',
          body: 'I want a saree',
        ),
      ];

  @override
  Future<Message> addMessage({
    required String conversationId,
    required String direction,
    required String source,
    required String body,
    DateTime? sentAt,
    Map<String, dynamic> meta = const {},
  }) async {
    addedMessages.add({
      'conversationId': conversationId,
      'direction': direction,
      'source': source,
      'body': body,
    });
    return Message(
      id: 'm-new',
      conversationId: conversationId,
      direction: direction,
      source: source,
      body: body,
    );
  }
}

class FakeSummaryService implements CustomerSummaryService {
  final AiSummary? _summary;
  bool refreshCalled = false;

  FakeSummaryService([this._summary]);

  @override
  Future<AiSummary?> fetch(String customerId) async => _summary;

  @override
  Future<AiSummary?> refresh(String customerId) async {
    refreshCalled = true;
    return _summary;
  }
}

class FakeDraftService implements DraftReplyService {
  final DraftReply? _reply;
  bool generateCalled = false;

  FakeDraftService([this._reply]);

  @override
  Future<DraftReply?> generate({
    required String customerId,
    required String objective,
  }) async {
    generateCalled = true;
    return _reply;
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

ProviderContainer makeContainer({
  FakeConvService? conv,
  FakeSummaryService? summary,
  FakeDraftService? draft,
  String customerId = 'c-1',
}) {
  return ProviderContainer(
    overrides: [
      conversationsServiceProvider
          .overrideWithValue(conv ?? FakeConvService()),
      customerSummaryServiceProvider
          .overrideWithValue(summary ?? FakeSummaryService()),
      draftReplyServiceProvider
          .overrideWithValue(draft ?? FakeDraftService()),
    ],
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  test('initial load fetches messages for customer', () async {
    final c = makeContainer();
    addTearDown(c.dispose);

    await c.read(conversationNotifierProvider('c-1').notifier).load();

    final state = c.read(conversationNotifierProvider('c-1'));
    expect(state.messages, isNotEmpty);
    expect(state.messages.first.body, 'I want a saree');
  });

  test('logAiSend appends message to state and persists', () async {
    final fakeConv = FakeConvService();
    final c = makeContainer(conv: fakeConv);
    addTearDown(c.dispose);

    await c.read(conversationNotifierProvider('c-1').notifier).load();

    await c
        .read(conversationNotifierProvider('c-1').notifier)
        .logAiSend('c-1', 'Hello Priya!');

    final state = c.read(conversationNotifierProvider('c-1'));
    final aiMsg = state.messages.firstWhere((m) => m.isAiSend);
    expect(aiMsg.body, 'Hello Priya!');
    expect(aiMsg.source, 'ai_send');
    expect(aiMsg.direction, 'outbound');
    expect(fakeConv.addedMessages, hasLength(1));
  });

  test('requestDraft calls DraftReplyService and stores result', () async {
    final fakeDraft = FakeDraftService(
        const DraftReply(message: 'Hi there!', confidence: 0.88));
    final c = makeContainer(draft: fakeDraft);
    addTearDown(c.dispose);

    await c.read(conversationNotifierProvider('c-1').notifier).load();

    await c
        .read(conversationNotifierProvider('c-1').notifier)
        .requestDraft('c-1', objective: 'reply');

    expect(fakeDraft.generateCalled, isTrue);
    final state = c.read(conversationNotifierProvider('c-1'));
    expect(state.draft?.message, 'Hi there!');
    expect(state.draft?.confidence, closeTo(0.88, 0.001));
  });

  test('requestDraft sets draftLoading true while in flight', () async {
    final fakeDraft = FakeDraftService(null);
    final c = makeContainer(draft: fakeDraft);
    addTearDown(c.dispose);

    await c.read(conversationNotifierProvider('c-1').notifier).load();

    // Fire without await to observe loading state
    final future = c
        .read(conversationNotifierProvider('c-1').notifier)
        .requestDraft('c-1', objective: 'reply');

    // draftLoading should be true before resolution
    expect(c.read(conversationNotifierProvider('c-1')).draftLoading, isTrue);
    await future;
    expect(c.read(conversationNotifierProvider('c-1')).draftLoading, isFalse);
  });

  test('clearDraft removes draft from state', () async {
    final fakeDraft = FakeDraftService(
        const DraftReply(message: 'Hi', confidence: 0.7));
    final c = makeContainer(draft: fakeDraft);
    addTearDown(c.dispose);

    await c.read(conversationNotifierProvider('c-1').notifier).load();
    await c
        .read(conversationNotifierProvider('c-1').notifier)
        .requestDraft('c-1', objective: 'reply');

    c.read(conversationNotifierProvider('c-1').notifier).clearDraft();
    expect(c.read(conversationNotifierProvider('c-1')).draft, isNull);
  });
}
