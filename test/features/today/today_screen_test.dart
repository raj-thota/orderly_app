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

void main() {
  Widget harness({
    required List<Order> orders,
    required List<Enquiry> enquiries,
    required List<String> events,
    void Function(int)? onNavigate,
  }) {
    return ProviderScope(
      overrides: [
        ordersControllerProvider.overrideWith((ref) => _FixedOrders(orders)),
        enquiriesControllerProvider
            .overrideWith((ref) => _FixedEnquiries(enquiries)),
        userProfileProvider
            .overrideWith((ref) async => {'business_name': 'Raj'}),
        eventServiceProvider.overrideWithValue(EventService(
          sink: (row) async => events.add(row['name'] as String),
          currentUserId: () => 'u1',
        )),
      ],
      child: MaterialApp(
        home: TodayScreen(onNavigate: onNavigate ?? (_) {}),
      ),
    );
  }

  final dueEnquiry = Enquiry(
    status: 'follow',
    followUpDate: DateTime.now().subtract(const Duration(days: 1)),
    customerName: 'Meena',
  );

  testWidgets('renders brief numbers from orders and enquiries',
      (tester) async {
    final orders = [
      Order(grandTotal: 9500, payments: [
        Payment(amount: 9500, paidAt: DateTime.now()),
      ], createdAt: DateTime.now()),
      const Order(grandTotal: 12000), // outstanding
    ];
    await tester.pumpWidget(harness(
        orders: orders, enquiries: [dueEnquiry], events: []));
    await tester.pumpAndSettle();

    expect(find.text('₹12,000'), findsOneWidget); // outstanding
    expect(find.text('₹9,500'), findsOneWidget); // revenue today
    expect(find.textContaining('Raj'), findsOneWidget); // greeting
    expect(find.text('Start My Work'), findsOneWidget);
  });

  testWidgets('Start My Work navigates to tab 1', (tester) async {
    int? navigated;
    await tester.pumpWidget(harness(
        orders: [], enquiries: [], events: [], onNavigate: (i) => navigated = i));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start My Work'));
    expect(navigated, 1);
  });

  testWidgets('tracks brief_view once on open', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(harness(orders: [], enquiries: [], events: events));
    await tester.pumpAndSettle();
    expect(events, ['brief_view']);
  });
}
