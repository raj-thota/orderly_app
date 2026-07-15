import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/customers/controller/customer_profile_provider.dart';
import 'package:orderly_app/features/customers/data/customer_stats.dart';
import 'package:orderly_app/features/customers/presentation/customer_profile_screen.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';

import '../orders/orders_controller_test.dart' show FakeOrdersService;
import 'customer_profile_provider_test.dart' show FakeStatsService;

CustomerStats _stats({
  String id = 'c1',
  String name = 'Priya Sharma',
  double ltv = 15000,
  double outstanding = 2000,
  int orders = 3,
  List<AiFact> facts = const [AiFact(fact: 'Prefers evening replies')],
}) =>
    CustomerStats(
      customerId: id,
      name: name,
      phone: '9876543210',
      totalOrders: orders,
      lifetimeValue: ltv,
      outstanding: outstanding,
      lastContactAt: DateTime.now().subtract(const Duration(days: 3)),
      aiFacts: facts,
    );

Widget _wrap({
  CustomerStats? stats,
  List<Order> orders = const [],
}) {
  final st = stats ?? _stats();
  return ProviderScope(
    overrides: [
      customerStatsServiceProvider
          .overrideWithValue(FakeStatsService({'c1': st})),
      ordersServiceProvider.overrideWithValue(FakeOrdersService(orders)),
    ],
    child: MaterialApp(
      home: CustomerProfileScreen(
        customerId: 'c1',
        customerName: st.name,
      ),
    ),
  );
}

void main() {
  testWidgets('shows customer name', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Priya Sharma'), findsWidgets);
  });

  testWidgets('shows lifetime value and outstanding', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.textContaining('15,000'), findsWidgets);
    expect(find.textContaining('2,000'), findsWidgets);
  });

  testWidgets('shows ai_facts bullets', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Prefers evening replies'), findsOneWidget);
  });

  testWidgets('shows relationship score', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    // Score label or stars present
    expect(find.textContaining('Score'), findsWidgets);
  });

  testWidgets('shows Open Chat button', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Open Chat'), findsOneWidget);
  });
}
