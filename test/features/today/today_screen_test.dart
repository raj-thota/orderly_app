import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import '../work/work_items_provider_test.dart' show FakeAiWorkItemsService;

class _RouteObserver extends NavigatorObserver {
  _RouteObserver({required this.onPush});
  final void Function(Route<dynamic>) onPush;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPush(route);
  }
}

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

final _trialSub = Subscription(
  id: 's1',
  userId: 'u1',
  plan: 'pro_monthly',
  status: 'trialing',
  trialEnd: DateTime.now().add(const Duration(days: 30)),
  createdAt: DateTime(2026, 1, 1),
);

Widget _harness({
  List<Order> orders = const [],
  List<Enquiry> enquiries = const [],
  List<String>? events,
  void Function(int)? onNavigate,
  FakeAiWorkItemsService? workItems,
  Map<String, dynamic>? profile,
  Subscription? sub,
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
      subscriptionProvider
          .overrideWith((ref) => Stream.value(sub ?? _trialSub)),
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
  testWidgets('snapshot tiles show outstanding and revenue from orders',
      (t) async {
    final orders = [
      Order(grandTotal: 9500, payments: [
        Payment(amount: 9500, paidAt: DateTime.now()),
      ], createdAt: DateTime.now()),
      const Order(grandTotal: 12000),
    ];
    await t.pumpWidget(_harness(orders: orders, enquiries: [_dueEnquiry]));
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('snap_outstanding')),
        matching: find.text('₹12,000'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('snap_revenue')),
        matching: find.text('₹9,500'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Raj'), findsOneWidget);
    expect(find.textContaining('Start My Work'), findsOneWidget);
  });

  testWidgets('Start My Work button launches Focus Mode', (t) async {
    SharedPreferences.setMockInitialValues({});
    final svc = FakeAiWorkItemsService([_workItem(customerName: 'Priya')]);

    // Track pushes via a NavigatorObserver spy.
    final pushed = <Route<dynamic>>[];
    final observer = _RouteObserver(onPush: pushed.add);

    await t.pumpWidget(ProviderScope(
      overrides: [
        ordersControllerProvider.overrideWith((ref) => _FixedOrders([])),
        enquiriesControllerProvider
            .overrideWith((ref) => _FixedEnquiries([])),
        userProfileProvider
            .overrideWith((ref) async => {'business_name': 'Raj'}),
        eventServiceProvider.overrideWithValue(EventService(
          sink: (row) async {},
          currentUserId: () => 'u1',
        )),
        aiWorkItemsServiceProvider.overrideWithValue(svc),
        conversationsServiceProvider.overrideWithValue(_FakeConv()),
        customerSummaryServiceProvider.overrideWithValue(_FakeSummary()),
        draftReplyServiceProvider.overrideWithValue(_FakeDraft()),
        subscriptionProvider.overrideWith((ref) => Stream.value(_trialSub)),
      ],
      child: MaterialApp(
        navigatorObservers: [observer],
        home: TodayScreen(onNavigate: (_) {}),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('Start My Work →'));
    // Pump one frame so Navigator processes the push without running
    // the Orbit animation loop (pumpAndSettle would time out).
    await t.pump();

    expect(pushed, isNotEmpty,
        reason: 'FocusMode.start should have pushed a route');
  });

  testWidgets('tracks brief_view once on open', (t) async {
    final events = <String>[];
    await t.pumpWidget(_harness(events: events));
    await t.pumpAndSettle();
    expect(events, ['brief_view']);
  });

  testWidgets('hero brief lists pending work as a check-list', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Priya', amount: 3360),
      _workItem(id: '2', kind: 'follow_up', customerName: 'Aman'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.textContaining('Collect ₹3,360 from 1 customer'),
        findsOneWidget);
    expect(find.textContaining('Reply to 1 waiting customer'), findsOneWidget);
    // One circular check icon per task, replacing the old bullets.
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
  });

  testWidgets('brief goes straight to the check-list, no intro line',
      (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Priya', amount: 3360),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text("Here's what I'd focus on today:"), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('no check-list when the day is all clear', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets('hero shows all-clear brief when nothing is pending', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.textContaining('All clear'), findsOneWidget);
  });

  testWidgets('hero shows session length and work list shows progress',
      (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Priya', amount: 3360),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text('1 task · about 2 min'), findsOneWidget);
    expect(find.text('🕒 About 2 min'), findsOneWidget);
    expect(find.text('✓ 0 / 1 completed'), findsOneWidget);
    // Completion count carries the Closr purple accent, not muted gray.
    final count = t.widget<Text>(find.text('✓ 0 / 1 completed'));
    expect(count.style?.color, AppColors.primary);
  });

  testWidgets('work progress updates as tasks complete', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(id: '1', customerName: 'Priya', amount: 3360),
      _workItem(id: '2', kind: 'follow_up', customerName: 'Aman'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text('🕒 About 5 min'), findsOneWidget);
    expect(find.text('✓ 0 / 2 completed'), findsOneWidget);

    final container = ProviderScope.containerOf(
        t.element(find.byType(TodayScreen)));
    await container.read(workItemsProvider.notifier).markDone('1');
    await t.pump();

    expect(find.text('🕒 About 3 min'), findsOneWidget);
    expect(find.text('✓ 1 / 2 completed'), findsOneWidget);
  });

  testWidgets('follow-up insight is an action card naming the customer',
      (t) async {
    int? navigated;
    await t.pumpWidget(_harness(
        enquiries: [_dueEnquiry],
        onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Reply to an interested customer'));
    expect(find.textContaining('Meena has been waiting'), findsOneWidget);
    expect(find.text('Reply now →'), findsOneWidget);

    await t.tap(find.text('Reply to an interested customer'));
    expect(navigated, 1);
  });

  testWidgets('outstanding insight tap navigates to Orders tab', (t) async {
    int? navigated;
    await t.pumpWidget(_harness(
        orders: [const Order(grandTotal: 12000)],
        onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Collect outstanding payments'));
    expect(find.text('₹12,000 is pending across 1 order.'), findsOneWidget);

    await t.tap(find.text('Collect outstanding payments'));
    expect(navigated, 2);
  });

  testWidgets("shows Today's work queue when work items exist", (t) async {
    final svc = FakeAiWorkItemsService([_workItem(customerName: 'Priya')]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text("Today's Work"), findsOneWidget);
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

  testWidgets('work row states the task with customer name and time',
      (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Rekha Joshi', amount: 3360),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text('Collect ₹3,360 from Rekha Joshi'), findsOneWidget);
    expect(find.text('2 min'), findsOneWidget);
  });

  testWidgets('insights hidden when brief has no items', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.text('AI insights'), findsNothing);
    expect(find.text('Collect outstanding payments'), findsNothing);
  });

  testWidgets('snapshot shows all 4 metric labels', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.text('Orders today'), findsOneWidget);
    expect(find.text('Revenue today'), findsOneWidget);
    expect(find.text('Outstanding'), findsOneWidget);
    expect(find.text('Follow-ups due'), findsOneWidget);
  });

  testWidgets('recent activity lists payments and orders', (t) async {
    final orders = [
      Order(
        customerName: 'Meena',
        grandTotal: 9500,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        payments: [
          Payment(
              amount: 9500,
              paidAt: DateTime.now().subtract(const Duration(hours: 1))),
        ],
      ),
    ];
    await t.pumpWidget(_harness(orders: orders));
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Recent activity'));
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('New order'), findsOneWidget);
    expect(find.text('+₹9,500'), findsOneWidget);
    expect(find.textContaining('Meena ·'), findsNWidgets(2));
  });

  testWidgets('recent activity hidden when there are no orders', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.text('Recent activity'), findsNothing);
  });

  testWidgets('quick actions render and Payments navigates to Orders tab',
      (t) async {
    int? navigated;
    await t.pumpWidget(_harness(onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Quick actions'));
    expect(find.text('New sale'), findsOneWidget);
    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);

    await t.tap(find.text('Payments'));
    expect(navigated, 2);
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

  testWidgets('tapping a work row opens the customer workspace', (t) async {
    int? navigated;
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Priya', kind: 'reply'),
    ]);
    await t.pumpWidget(_harness(workItems: svc, onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('Reply to Priya'));
    await t.tap(find.text('Reply to Priya'));
    await t.pumpAndSettle();

    // Workspace screen is unique: it has a Chat tab.
    expect(find.text('Chat'), findsOneWidget);
    expect(navigated, isNull);
  });

  group('plan nudge', () {
    testWidgets('hidden while the trial has plenty of time left', (t) async {
      await t.pumpWidget(_harness());
      await t.pumpAndSettle();
      expect(find.byKey(const Key('today_plan_nudge')), findsNothing);
    });

    testWidgets('shows countdown when the trial ends within 3 days', (t) async {
      final endingSub = Subscription(
        id: 's1',
        userId: 'u1',
        plan: 'pro_monthly',
        status: 'trialing',
        trialEnd: DateTime.now().add(const Duration(days: 2)),
        createdAt: DateTime(2026, 1, 1),
      );
      await t.pumpWidget(_harness(sub: endingSub));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('today_plan_nudge')), findsOneWidget);
      expect(find.textContaining('trial ends in'), findsOneWidget);
    });

    testWidgets('shows trial-ended copy and opens the plans screen when gated',
        (t) async {
      final gatedSub = Subscription(
        id: 's1',
        userId: 'u1',
        plan: 'pro_monthly',
        status: 'expired',
        createdAt: DateTime(2026, 1, 1),
      );
      await t.pumpWidget(_harness(sub: gatedSub));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('today_plan_nudge')), findsOneWidget);
      expect(find.textContaining('trial has ended'), findsOneWidget);

      await t.tap(find.byKey(const Key('today_plan_nudge')));
      await t.pumpAndSettle();
      expect(find.text('Free forever'), findsOneWidget);
    });
  });
}
