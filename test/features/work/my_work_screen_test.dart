import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';
import 'package:orderly_app/features/work/presentation/my_work_screen.dart';

import 'work_items_provider_test.dart' show FakeAiWorkItemsService;

AiWorkItem _item(String id, {String priority = 'high', String? name}) =>
    AiWorkItem(
      id: id,
      kind: 'payment_reminder',
      priority: priority,
      score: 80,
      title: 'Payment pending',
      context: 'Order #$id outstanding',
      status: 'pending',
      batchId: 'b-1',
      customerId: 'c-$id',
      customerName: name ?? 'Customer $id',
      amount: 5000,
      draftMessage: 'Hi! Your payment is due.',
    );

Widget wrap(List<AiWorkItem> items) => ProviderScope(
      overrides: [
        aiWorkItemsServiceProvider
            .overrideWithValue(FakeAiWorkItemsService(items)),
      ],
      child: const MaterialApp(home: MyWorkScreen()),
    );

void main() {
  testWidgets('shows My Work title', (t) async {
    await t.pumpWidget(wrap([]));
    await t.pumpAndSettle();
    expect(find.text('My Work'), findsOneWidget);
  });

  testWidgets('shows empty state when no items', (t) async {
    await t.pumpWidget(wrap([]));
    await t.pumpAndSettle();
    expect(find.textContaining('all caught up'), findsOneWidget);
  });

  testWidgets('renders item cards with title and customer name', (t) async {
    await t.pumpWidget(wrap([
      _item('1', name: 'Priya'),
      _item('2', priority: 'medium', name: 'Rahul'),
    ]));
    await t.pumpAndSettle();
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Rahul'), findsOneWidget);
    expect(find.text('Payment pending'), findsWidgets);
  });

  testWidgets('High/Medium/Low filter tabs appear', (t) async {
    await t.pumpWidget(wrap([_item('1')]));
    await t.pumpAndSettle();
    expect(find.textContaining('All'), findsOneWidget);
    expect(find.textContaining('High'), findsOneWidget);
    expect(find.textContaining('Medium'), findsOneWidget);
    expect(find.textContaining('Low'), findsOneWidget);
  });

  testWidgets('High tab only shows high priority items', (t) async {
    await t.pumpWidget(wrap([
      _item('1', priority: 'high', name: 'Priya'),
      _item('2', priority: 'low', name: 'Rahul'),
    ]));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('High ('));
    await t.pumpAndSettle();
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Rahul'), findsNothing);
  });
}
