import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/assistant/controller/assistant_chat_provider.dart';
import 'package:orderly_app/features/assistant/data/assistant_message.dart';
import 'package:orderly_app/features/assistant/data/assistant_service.dart';

class FakeAssistantService implements AssistantService {
  final AssistantResponse response;
  int askCalled = 0;
  int confirmCalled = 0;

  FakeAssistantService({
    this.response = const AssistantResponse(
      answer: 'You have 2 pending payments.',
      suggestions: ['Send reminder'],
      proposedWorkItems: [],
    ),
  });

  @override
  Future<AssistantResponse> ask({
    required String question,
    String? customerId,
    List<Map<String, dynamic>> history = const [],
  }) async {
    askCalled++;
    return response;
  }

  @override
  Future<void> confirmWorkItem(ProposedWorkItem item) async {
    confirmCalled++;
  }
}

ProviderContainer _makeContainer(FakeAssistantService svc) {
  return ProviderContainer(
    overrides: [
      assistantServiceProvider.overrideWithValue(svc),
    ],
  );
}

void main() {
  test('initial state has empty turns and is not thinking', () {
    final svc = FakeAssistantService();
    final container = _makeContainer(svc);
    addTearDown(container.dispose);

    final state = container.read(assistantChatProvider);
    expect(state.turns, isEmpty);
    expect(state.thinking, isFalse);
    expect(state.error, isNull);
  });

  test('send adds user turn then assistant turn', () async {
    final svc = FakeAssistantService();
    final container = _makeContainer(svc);
    addTearDown(container.dispose);

    await container.read(assistantChatProvider.notifier).send('How much is pending?');

    final state = container.read(assistantChatProvider);
    expect(state.turns.length, 2);
    expect(state.turns[0].role, 'user');
    expect(state.turns[0].text, 'How much is pending?');
    expect(state.turns[1].role, 'assistant');
    expect(state.turns[1].text, 'You have 2 pending payments.');
    expect(state.thinking, isFalse);
    expect(svc.askCalled, 1);
  });

  test('send passes history of prior turns to service', () async {
    List<Map<String, dynamic>>? capturedHistory;
    final container = ProviderContainer(
      overrides: [
        assistantServiceProvider.overrideWith((_) {
          return _HistoryCaptureFake(
            onAsk: (h) => capturedHistory = h,
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(assistantChatProvider.notifier);
    await notifier.send('First question');
    await notifier.send('Second question');

    expect(capturedHistory, isNotNull);
    expect(capturedHistory!.length, 2);
    expect(capturedHistory![0]['role'], 'user');
    expect(capturedHistory![1]['role'], 'assistant');
  });

  test('proposed work items attach to assistant turn', () async {
    final item = ProposedWorkItem.fromMap({
      'kind': 'payment_reminder',
      'customer_id': 'c1',
      'customer_name': 'Priya',
      'draft_message': 'Pay up.',
      'priority': 'high',
    });
    final svc = FakeAssistantService(
      response: AssistantResponse(
        answer: 'Here is a reminder.',
        suggestions: [],
        proposedWorkItems: [item],
      ),
    );
    final container = _makeContainer(svc);
    addTearDown(container.dispose);

    await container.read(assistantChatProvider.notifier).send('Create reminders');

    final state = container.read(assistantChatProvider);
    final assistantTurn = state.turns.last;
    expect(assistantTurn.proposedItems.length, 1);
    expect(assistantTurn.proposedItems.first.kind, 'payment_reminder');
  });

  test('approveProposedItem calls service confirmWorkItem', () async {
    final item = ProposedWorkItem.fromMap({
      'kind': 'payment_reminder',
      'customer_id': 'c1',
      'customer_name': 'Priya',
      'draft_message': 'Pay up.',
      'priority': 'high',
    });
    final svc = FakeAssistantService(
      response: AssistantResponse(
        answer: 'Done.',
        suggestions: [],
        proposedWorkItems: [item],
      ),
    );
    final container = _makeContainer(svc);
    addTearDown(container.dispose);

    await container.read(assistantChatProvider.notifier).send('remind Priya');
    await container.read(assistantChatProvider.notifier).approveProposedItem(item);

    expect(svc.confirmCalled, 1);
  });

  test('error from service sets error state and keeps prior turns', () async {
    final container = ProviderContainer(
      overrides: [
        assistantServiceProvider.overrideWith((_) => _ThrowingFake()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(assistantChatProvider.notifier).send('What is 2+2?');

    final state = container.read(assistantChatProvider);
    expect(state.error, isNotNull);
    expect(state.thinking, isFalse);
    // user turn should still be present
    expect(state.turns.length, 1);
    expect(state.turns.first.role, 'user');
  });
}

class _HistoryCaptureFake implements AssistantService {
  final void Function(List<Map<String, dynamic>>) onAsk;
  _HistoryCaptureFake({required this.onAsk});

  @override
  Future<AssistantResponse> ask({
    required String question,
    String? customerId,
    List<Map<String, dynamic>> history = const [],
  }) async {
    onAsk(history);
    return const AssistantResponse(
      answer: 'ok',
      suggestions: [],
      proposedWorkItems: [],
    );
  }

  @override
  Future<void> confirmWorkItem(ProposedWorkItem item) async {}
}

class _ThrowingFake implements AssistantService {
  @override
  Future<AssistantResponse> ask({
    required String question,
    String? customerId,
    List<Map<String, dynamic>> history = const [],
  }) async {
    throw Exception('network error');
  }

  @override
  Future<void> confirmWorkItem(ProposedWorkItem item) async {}
}
