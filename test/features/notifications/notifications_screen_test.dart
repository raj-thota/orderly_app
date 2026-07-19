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
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

import '../work/work_items_provider_test.dart' show FakeAiWorkItemsService;

// ─── Workspace fakes (so tapping a row can push CustomerWorkspaceScreen) ───────

class _FakeConv implements ConversationsService {
  @override
  Future<Conversation> getOrCreate(String id) async =>
      Conversation(id: 'cv-1', customerId: id);
  @override
  Future<Conversation?> fetchByCustomerId(String id) async =>
      Conversation(id: 'cv-1', customerId: id);
  @override
  Future<List<Message>> fetchMessages(String _) async => const [];
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
  @override
  Future<AiSummary?> fetch(String _) async => null;
  @override
  Future<AiSummary?> refresh(String _) async => null;
}

class _FakeDraft implements DraftReplyService {
  @override
  Future<DraftReply?> generate(
          {required String customerId, required String objective}) async =>
      null;
}

AiWorkItem _item({
  String id = '1',
  String kind = 'payment_reminder',
  String priority = 'high',
  String? name,
  String? phone,
  DateTime? createdAt,
}) =>
    AiWorkItem(
      id: id,
      kind: kind,
      priority: priority,
      score: 80,
      title: 'Payment pending',
      status: 'pending',
      batchId: 'b-1',
      customerId: 'c-$id',
      customerName: name ?? 'Customer $id',
      phone: phone,
      createdAt: createdAt,
    );

Widget _wrap(List<AiWorkItem> items) => ProviderScope(
      overrides: [
        aiWorkItemsServiceProvider
            .overrideWithValue(FakeAiWorkItemsService(items)),
        conversationsServiceProvider.overrideWithValue(_FakeConv()),
        customerSummaryServiceProvider.overrideWithValue(_FakeSummary()),
        draftReplyServiceProvider.overrideWithValue(_FakeDraft()),
        entitlementProvider.overrideWith((_) => EntitlementStatus.trialing),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    );

void main() {
  testWidgets('shows empty state when no work items', (t) async {
    await t.pumpWidget(_wrap([]));
    await t.pumpAndSettle();
    expect(find.textContaining('All caught up'), findsOneWidget);
  });

  testWidgets('lists a work item with customer name and title', (t) async {
    await t.pumpWidget(_wrap([_item(name: 'Priya')]));
    await t.pumpAndSettle();
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Payment pending'), findsOneWidget);
  });

  testWidgets('shows an Urgent section when a high-priority item exists',
      (t) async {
    await t.pumpWidget(_wrap([_item(priority: 'high', name: 'Priya')]));
    await t.pumpAndSettle();
    expect(find.textContaining('Urgent'), findsOneWidget);
  });

  testWidgets('groups non-high items under Needs attention', (t) async {
    await t.pumpWidget(_wrap([
      _item(id: '1', priority: 'medium', name: 'Rahul'),
    ]));
    await t.pumpAndSettle();
    expect(find.textContaining('Needs attention'), findsOneWidget);
    expect(find.textContaining('Urgent'), findsNothing);
  });

  testWidgets('tapping a notification opens the customer workspace', (t) async {
    await t.pumpWidget(_wrap([_item(name: 'Priya', kind: 'reply')]));
    await t.pumpAndSettle();

    await t.tap(find.text('Priya'));
    await t.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('action button with no phone opens the workspace', (t) async {
    await t.pumpWidget(_wrap([_item(id: '9', name: 'Priya')]));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('notif_action_9')));
    await t.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('Done removes the notification from the list', (t) async {
    await t.pumpWidget(_wrap([_item(id: '7', name: 'Priya')]));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('notif_done_7')));
    await t.pumpAndSettle();

    expect(find.text('Priya'), findsNothing);
    expect(find.textContaining('All caught up'), findsOneWidget);
  });

  testWidgets('renders a relative timestamp when createdAt is set', (t) async {
    await t.pumpWidget(_wrap([
      _item(name: 'Priya', createdAt: DateTime.now().subtract(const Duration(hours: 2))),
    ]));
    await t.pumpAndSettle();
    expect(find.textContaining('2h ago'), findsOneWidget);
  });

  testWidgets('swiping a tile dismisses it', (t) async {
    await t.pumpWidget(_wrap([_item(id: '3', name: 'Priya')]));
    await t.pumpAndSettle();

    await t.drag(find.text('Priya'), const Offset(-500, 0));
    await t.pumpAndSettle();

    expect(find.text('Priya'), findsNothing);
    expect(find.text('Dismissed'), findsOneWidget);
  });

  testWidgets('mark-all-done clears the list', (t) async {
    await t.pumpWidget(_wrap([
      _item(id: '1', name: 'Priya'),
      _item(id: '2', name: 'Rahul', priority: 'medium'),
    ]));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('notif_mark_all_done')));
    await t.pumpAndSettle();

    expect(find.text('Priya'), findsNothing);
    expect(find.text('Rahul'), findsNothing);
    expect(find.textContaining('All caught up'), findsOneWidget);
  });
}
