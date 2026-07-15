import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';
import 'package:orderly_app/features/payments/data/payment.dart';
import 'package:orderly_app/features/today/presentation/today_screen.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

import '../work/work_items_provider_test.dart' show FakeAiWorkItemsService;

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
}) {
  final captured = events ?? [];
  return ProviderScope(
    overrides: [
      ordersControllerProvider.overrideWith((ref) => _FixedOrders(orders)),
      enquiriesControllerProvider
          .overrideWith((ref) => _FixedEnquiries(enquiries)),
      userProfileProvider
          .overrideWith((ref) async => {'business_name': 'Raj'}),
      eventServiceProvider.overrideWithValue(EventService(
        sink: (row) async => captured.add(row['name'] as String),
        currentUserId: () => 'u1',
      )),
      aiWorkItemsServiceProvider
          .overrideWithValue(workItems ?? FakeAiWorkItemsService([])),
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

    expect(find.textContaining('Rekha Joshi'), findsOneWidget);
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
}
