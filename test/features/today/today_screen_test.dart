import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/conversations/controller/conversation_provider.dart';
import 'package:orderly_app/features/conversations/data/ai_summary.dart';
import 'package:orderly_app/features/conversations/data/conversation.dart';
import 'package:orderly_app/features/conversations/data/conversations_service.dart';
import 'package:orderly_app/features/conversations/data/customer_summary_service.dart';
import 'package:orderly_app/features/conversations/data/draft_reply_service.dart';
import 'package:orderly_app/features/conversations/data/message.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';
import 'package:orderly_app/features/payments/data/payment.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';
import 'package:orderly_app/features/today/presentation/today_screen.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

import '../work/work_items_provider_test.dart' show FakeAiWorkItemsService;

// ─── Workspace fakes (so tapping a card can push CustomerWorkspaceScreen) ──────

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

class _FixedOrders extends OrdersController {
  _FixedOrders(List<Order> orders) : super(OrdersService()) {
    state = AsyncValue.data(orders);
  }
  @override
  Future<void> load() async {}
}

class _FixedEnquiries extends EnquiriesController {
  _FixedEnquiries(List<Enquiry> enquiries) : super(EnquiriesService()) {
    state = AsyncValue.data(enquiries);
  }
  @override
  Future<void> load() async {}
}

Widget _harness({
  List<Order> orders = const [],
  List<Enquiry> enquiries = const [],
  List<String>? events,
  void Function(int)? onNavigate,
  FakeAiWorkItemsService? workItems,
  Map<String, dynamic>? profile,
}) {
  final captured = events ?? [];
  return ProviderScope(
    overrides: [
      ordersControllerProvider.overrideWith((ref) => _FixedOrders(orders)),
      enquiriesControllerProvider
          .overrideWith((ref) => _FixedEnquiries(enquiries)),
      userProfileProvider
          .overrideWith((ref) async => profile ?? {'business_name': 'Raj'}),
      eventServiceProvider.overrideWithValue(EventService(
        sink: (row) async => captured.add(row['name'] as String),
        currentUserId: () => 'u1',
      )),
      aiWorkItemsServiceProvider
          .overrideWithValue(workItems ?? FakeAiWorkItemsService([])),
      // Let a pushed CustomerWorkspaceScreen build without Supabase.
      conversationsServiceProvider.overrideWithValue(_FakeConv()),
      customerSummaryServiceProvider.overrideWithValue(_FakeSummary()),
      draftReplyServiceProvider.overrideWithValue(_FakeDraft()),
      entitlementProvider.overrideWith((_) => EntitlementStatus.trialing),
    ],
    child: MaterialApp(
      home: TodayScreen(onNavigate: onNavigate ?? (_) {}),
    ),
  );
}

final _dueEnquiry = Enquiry(
  status: 'follow',
  followUpDate: DateTime.now().subtract(const Duration(days: 1)),
  customerName: 'Meena',
);

AiWorkItem _workItem({
  String id = '1',
  String kind = 'payment_reminder',
  String priority = 'high',
  String? customerName,
  double? amount,
  String? phone,
}) =>
    AiWorkItem(
      id: id,
      kind: kind,
      priority: priority,
      score: 90,
      title: 'Payment pending',
      status: 'pending',
      batchId: 'b-1',
      customerId: 'c-1',
      customerName: customerName,
      amount: amount,
      phone: phone,
    );

void main() {
  testWidgets('renders brief stat tile values from orders and enquiries',
      (t) async {
    final orders = [
      Order(grandTotal: 9500, payments: [
        Payment(amount: 9500, paidAt: DateTime.now()),
      ], createdAt: DateTime.now()),
      const Order(grandTotal: 12000),
    ];
    await t.pumpWidget(_harness(orders: orders, enquiries: [_dueEnquiry]));
    await t.pumpAndSettle();

    expect(find.text('₹12,000'), findsOneWidget);
    expect(find.text('₹9,500'), findsOneWidget);
    expect(find.textContaining('Raj'), findsOneWidget);
    expect(find.textContaining('Start My Work'), findsOneWidget);
  });

  testWidgets('Start My Work button navigates to tab 1', (t) async {
    int? navigated;
    await t.pumpWidget(_harness(onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.tap(find.textContaining('Start My Work'));
    expect(navigated, 1);
  });

  testWidgets('tracks brief_view once on open', (t) async {
    final events = <String>[];
    await t.pumpWidget(_harness(events: events));
    await t.pumpAndSettle();
    expect(events, ['brief_view']);
  });

  testWidgets('due nudge tap navigates to tab 1', (t) async {
    int? navigated;
    await t.pumpWidget(_harness(
        enquiries: [_dueEnquiry],
        onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.tap(find.textContaining('need your attention'));
    expect(navigated, 1);
  });

  testWidgets('shows Needs your attention section when work items exist',
      (t) async {
    final svc = FakeAiWorkItemsService([_workItem(customerName: 'Priya')]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text('Needs your attention'), findsOneWidget);
  });

  testWidgets('bell badge shows pending work item count', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(id: '1'),
      _workItem(id: '2'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('attention tile shows customer name and priority badge', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Rekha Joshi', priority: 'high'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.textContaining('Rekha Joshi'), findsAtLeastNWidgets(1));
    expect(find.text('High'), findsOneWidget);
  });

  testWidgets('attention tile shows formatted amount', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Aman', amount: 3360),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.textContaining('₹3,360'), findsOneWidget);
  });

  testWidgets('AI suggested actions section visible when work items exist',
      (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Deepika', kind: 'follow_up'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.textContaining('AI suggested actions'), findsOneWidget);
    expect(find.textContaining('Call follow-up for Deepika'), findsOneWidget);
  });

  testWidgets('nudge section hidden when brief has no items', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.textContaining('need your attention'), findsNothing);
    expect(find.textContaining('outstanding'), findsNothing);
  });

  testWidgets('glance card shows all 4 stat tile labels', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.textContaining('Follow-ups'), findsOneWidget);
    expect(find.textContaining('Orders'), findsOneWidget);
    expect(find.textContaining('Revenue'), findsOneWidget);
    expect(find.textContaining('Outstanding'), findsOneWidget);
  });

  testWidgets('app bar shows a profile avatar, not a hamburger menu',
      (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.byIcon(Icons.menu_rounded), findsNothing);
    expect(find.byKey(const Key('today_profile_avatar')), findsOneWidget);
  });

  testWidgets('profile avatar shows initial letter when no photo', (t) async {
    await t.pumpWidget(_harness(profile: {'business_name': 'Raj'}));
    await t.pumpAndSettle();

    final avatar = t.widget<CircleAvatar>(
        find.byKey(const Key('today_profile_avatar')));
    expect(avatar.backgroundImage, isNull);
    expect(find.descendant(
      of: find.byKey(const Key('today_profile_avatar')),
      matching: find.text('R'),
    ), findsOneWidget);
  });

  test('profileAvatarImage returns null when no url', () {
    expect(profileAvatarImage(null), isNull);
    expect(profileAvatarImage(''), isNull);
  });

  test('profileAvatarImage returns NetworkImage for a url', () {
    final image = profileAvatarImage('https://example.com/me.png');
    expect(image, isA<NetworkImage>());
    expect((image as NetworkImage).url, 'https://example.com/me.png');
  });

  testWidgets('tapping an attention tile opens the customer workspace',
      (t) async {
    int? navigated;
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Priya', kind: 'reply'),
    ]);
    await t.pumpWidget(_harness(workItems: svc, onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.tap(find.text('Priya'));
    await t.pumpAndSettle();

    // Workspace screen is unique: it has a Chat tab.
    expect(find.text('Chat'), findsOneWidget);
    expect(navigated, isNull);
  });

  testWidgets('AI action card with no phone opens the workspace', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Priya', kind: 'payment_reminder'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    await t.ensureVisible(find.textContaining('Send price to Priya'));
    await t.tap(find.textContaining('Send price to Priya'));
    await t.pumpAndSettle();

    expect(find.text('Chat'), findsOneWidget);
  });
}
