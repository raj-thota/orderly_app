import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/presentation/order_detail_screen.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;

void main() {
  Widget wrap(Order order, {String? upiId}) {
    return ProviderScope(
      overrides: [
        ordersServiceProvider.overrideWithValue(FakeOrdersService([order])),
        businessProfileProvider.overrideWith(
            (ref) async => BusinessProfile(name: 'Shop', upiId: upiId)),
      ],
      child: MaterialApp(home: OrderDetailScreen(order: order)),
    );
  }

  testWidgets('shows paid/dues and both actions when dues remain', (tester) async {
    final order = Order.fromMap({
      'id': 'o1',
      'order_number': 7,
      'grand_total': '5000',
      'status': 'pending',
      'payments': [
        {'amount': '2000'},
      ],
    });
    await tester.pumpWidget(wrap(order, upiId: 'shop@upi'));
    await tester.pumpAndSettle();

    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('Collect via UPI'), findsOneWidget);
    expect(find.textContaining('3,000'), findsWidgets); // dues = 5000 - 2000
  });

  testWidgets('hides UPI action when no upi id is set', (tester) async {
    final order = Order.fromMap({
      'id': 'o1',
      'grand_total': '5000',
      'status': 'pending',
      'payments': [
        {'amount': '2000'},
      ],
    });
    await tester.pumpWidget(wrap(order)); // no upiId
    await tester.pumpAndSettle();

    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('Collect via UPI'), findsNothing);
  });

  testWidgets('hides payment actions when fully paid', (tester) async {
    final order = Order.fromMap({
      'id': 'o1',
      'grand_total': '1000',
      'status': 'delivered',
      'payment_status': 'paid',
      'payments': [
        {'amount': '1000'},
      ],
    });
    await tester.pumpWidget(wrap(order, upiId: 'shop@upi'));
    await tester.pumpAndSettle();

    expect(find.text('Record payment'), findsNothing);
    expect(find.text('Collect via UPI'), findsNothing);
  });
}
