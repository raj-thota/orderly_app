import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/conversations/controller/conversation_provider.dart';
import 'package:orderly_app/features/conversations/data/ai_summary.dart';
import 'package:orderly_app/features/conversations/data/conversation.dart';
import 'package:orderly_app/features/conversations/data/conversations_service.dart';
import 'package:orderly_app/features/conversations/data/customer_summary_service.dart';
import 'package:orderly_app/features/conversations/data/draft_reply_service.dart';
import 'package:orderly_app/features/conversations/data/message.dart';
import 'package:orderly_app/features/conversations/presentation/customer_workspace_screen.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _FakeConv implements ConversationsService {
  @override
  Future<Conversation> getOrCreate(String id) async =>
      Conversation(id: 'cv-1', customerId: id);

  @override
  Future<Conversation?> fetchByCustomerId(String id) async =>
      Conversation(id: 'cv-1', customerId: id);

  @override
  Future<List<Message>> fetchMessages(String _) async => [
        Message(
          id: 'm-1',
          conversationId: 'cv-1',
          direction: 'inbound',
          source: 'paste',
          body: 'Hi, I want 2 sarees',
        ),
        Message(
          id: 'm-2',
          conversationId: 'cv-1',
          direction: 'outbound',
          source: 'ai_send',
          body: 'Sure! Here is your quote.',
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
  }) async =>
      Message(
        id: 'm-new',
        conversationId: conversationId,
        direction: direction,
        source: source,
        body: body,
      );
}

class _FakeSummary implements CustomerSummaryService {
  final AiSummary? _s;
  _FakeSummary([this._s]);

  @override
  Future<AiSummary?> fetch(String _) async => _s;

  @override
  Future<AiSummary?> refresh(String _) async => _s;
}

class _FakeDraft implements DraftReplyService {
  @override
  Future<DraftReply?> generate(
          {required String customerId, required String objective}) async =>
      const DraftReply(message: 'Hello Priya!', confidence: 0.88);
}

// ─── Helper ──────────────────────────────────────────────────────────────────

Widget wrap(Widget child,
    {CustomerSummaryService? summary, DraftReplyService? draft}) {
  return ProviderScope(
    overrides: [
      conversationsServiceProvider.overrideWithValue(_FakeConv()),
      customerSummaryServiceProvider
          .overrideWithValue(summary ?? _FakeSummary()),
      draftReplyServiceProvider.overrideWithValue(draft ?? _FakeDraft()),
      entitlementProvider.overrideWith((_) => EntitlementStatus.trialing),
    ],
    child: MaterialApp(home: child),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  testWidgets('shows customer name in app bar', (t) async {
    await t.pumpWidget(wrap(const CustomerWorkspaceScreen(
      customerId: 'c-1',
      customerName: 'Priya Sharma',
    )));
    await t.pumpAndSettle();
    expect(find.text('Priya Sharma'), findsOneWidget);
  });

  testWidgets('Chat tab shows message bubbles', (t) async {
    await t.pumpWidget(wrap(const CustomerWorkspaceScreen(
      customerId: 'c-1',
      customerName: 'Priya',
    )));
    await t.pumpAndSettle();
    expect(find.text('Hi, I want 2 sarees'), findsOneWidget);
    expect(find.text('Sure! Here is your quote.'), findsOneWidget);
  });

  testWidgets('Summary tab shows AI summary when available', (t) async {
    final summary = AiSummary.fromMap({
      'id': 's-1',
      'customer_id': 'c-1',
      'bullets': ['Interested in sarees', 'Budget around ₹3000'],
      'close_confidence': 0.75,
    });
    await t.pumpWidget(wrap(
      const CustomerWorkspaceScreen(customerId: 'c-1', customerName: 'Priya'),
      summary: _FakeSummary(summary),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('Summary'));
    await t.pumpAndSettle();

    expect(find.textContaining('Interested in sarees'), findsOneWidget);
    expect(find.textContaining('Budget around'), findsOneWidget);
  });

  testWidgets('Summary tab shows empty state when no summary', (t) async {
    await t.pumpWidget(wrap(
      const CustomerWorkspaceScreen(customerId: 'c-1', customerName: 'Priya'),
      summary: _FakeSummary(null),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Summary'));
    await t.pumpAndSettle();
    expect(find.textContaining('No summary'), findsOneWidget);
  });

  testWidgets('Draft Reply button shows in Chat tab', (t) async {
    await t.pumpWidget(wrap(const CustomerWorkspaceScreen(
      customerId: 'c-1',
      customerName: 'Priya',
    )));
    await t.pumpAndSettle();
    expect(find.text('Draft Reply'), findsOneWidget);
  });
}
