import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/assistant/controller/assistant_chat_provider.dart';
import 'package:orderly_app/features/assistant/data/assistant_message.dart';
import 'package:orderly_app/features/assistant/data/assistant_service.dart';
import 'package:orderly_app/features/assistant/presentation/assistant_screen.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';

class _FakeFast implements AssistantService {
  final AssistantResponse response;
  _FakeFast({required this.response});

  @override
  Future<AssistantResponse> ask({
    required String question,
    String? customerId,
    List<Map<String, dynamic>> history = const [],
  }) async =>
      response;

  @override
  Future<void> confirmWorkItem(ProposedWorkItem item) async {}
}

final _trialSub = Subscription(
  id: 's1',
  userId: 'u1',
  plan: 'pro_monthly',
  status: 'trialing',
  trialEnd: DateTime.now().add(const Duration(days: 30)),
  createdAt: DateTime(2026, 1, 1),
);

Widget _wrap(AssistantService svc) {
  return ProviderScope(
    overrides: [
      assistantServiceProvider.overrideWithValue(svc),
      subscriptionProvider.overrideWith((ref) => Stream.value(_trialSub)),
    ],
    child: const MaterialApp(home: AssistantScreen()),
  );
}

void main() {
  testWidgets('shows empty state and input field', (t) async {
    await t.pumpWidget(_wrap(_FakeFast(
      response:
          const AssistantResponse(answer: '', suggestions: [], proposedWorkItems: []),
    )));
    await t.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('assistant_send')), findsOneWidget);
    expect(find.textContaining('Ask'), findsWidgets);
  });

  testWidgets('typing and sending shows user bubble', (t) async {
    final svc = _FakeFast(
      response: const AssistantResponse(
        answer: 'You have 3 pending payments.',
        suggestions: [],
        proposedWorkItems: [],
      ),
    );
    await t.pumpWidget(_wrap(svc));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'How much is outstanding?');
    await t.pump(); // apply setState(_canSend=true) so button is active
    await t.tap(find.byKey(const Key('assistant_send')));
    await t.pumpAndSettle();

    expect(find.textContaining('How much is outstanding'), findsWidgets);
    expect(find.textContaining('3 pending payments'), findsWidgets);
  });

  testWidgets('shows typing indicator while thinking', (t) async {
    final completer = Completer<AssistantResponse>();
    final svc = _SlowFake(completer: completer);
    await t.pumpWidget(_wrap(svc));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'Loading question');
    await t.pump(); // apply _canSend=true
    await t.tap(find.byKey(const Key('assistant_send')));
    // Process state change → widget rebuild with thinking:true
    await t.pump();
    await t.pump(const Duration(milliseconds: 10));

    expect(find.byKey(const Key('assistant_typing_indicator')), findsOneWidget);

    completer.complete(const AssistantResponse(
        answer: 'Done', suggestions: [], proposedWorkItems: []));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('assistant_typing_indicator')), findsNothing);
  });

  testWidgets('proposed work item shows Approve and Dismiss buttons', (t) async {
    // Tall surface so all chat items render without needing to scroll
    await t.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final item = ProposedWorkItem.fromMap({
      'kind': 'payment_reminder',
      'customer_id': 'c1',
      'customer_name': 'Priya Sharma',
      'draft_message': 'Hi Priya, your payment is due.',
      'priority': 'high',
    });
    final svc = _FakeFast(
      response: AssistantResponse(
        answer: 'I created a reminder for Priya.',
        suggestions: [],
        proposedWorkItems: [item],
      ),
    );
    await t.pumpWidget(_wrap(svc));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'Remind Priya');
    await t.pump(); // apply _canSend=true
    await t.tap(find.byKey(const Key('assistant_send')));
    await t.pumpAndSettle();

    expect(find.text('Priya Sharma'), findsWidgets);
    expect(find.byKey(const Key('approve_work_item_0')), findsOneWidget);
    expect(find.byKey(const Key('dismiss_work_item_0')), findsOneWidget);
  });

  testWidgets('dismissing proposed item removes it from UI', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final item = ProposedWorkItem.fromMap({
      'kind': 'payment_reminder',
      'customer_id': 'c1',
      'customer_name': 'Priya Sharma',
      'draft_message': 'Hi Priya, your payment is due.',
      'priority': 'high',
    });
    final svc = _FakeFast(
      response: AssistantResponse(
        answer: 'Reminder ready.',
        suggestions: [],
        proposedWorkItems: [item],
      ),
    );
    await t.pumpWidget(_wrap(svc));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'Remind Priya');
    await t.pump(); // apply _canSend=true
    await t.tap(find.byKey(const Key('assistant_send')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('dismiss_work_item_0')), findsOneWidget);
    await t.tap(find.byKey(const Key('dismiss_work_item_0')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('approve_work_item_0')), findsNothing);
  });
}

class _SlowFake implements AssistantService {
  final Completer<AssistantResponse> completer;
  _SlowFake({required this.completer});

  @override
  Future<AssistantResponse> ask({
    required String question,
    String? customerId,
    List<Map<String, dynamic>> history = const [],
  }) =>
      completer.future;

  @override
  Future<void> confirmWorkItem(ProposedWorkItem item) async {}
}
