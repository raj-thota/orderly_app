import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/assistant/data/assistant_message.dart';

void main() {
  group('ProposedWorkItem', () {
    test('fromMap parses all fields', () {
      final item = ProposedWorkItem.fromMap({
        'kind': 'payment_reminder',
        'customer_id': 'c1',
        'customer_name': 'Priya',
        'draft_message': 'Hi, your payment is due.',
        'priority': 'high',
      });
      expect(item.kind, 'payment_reminder');
      expect(item.customerId, 'c1');
      expect(item.customerName, 'Priya');
      expect(item.draftMessage, 'Hi, your payment is due.');
      expect(item.priority, 'high');
    });

    test('fromMap defaults priority to medium when missing', () {
      final item = ProposedWorkItem.fromMap({
        'kind': 'follow_up',
        'customer_id': 'c2',
        'customer_name': 'Raj',
        'draft_message': 'Just checking in.',
      });
      expect(item.priority, 'medium');
    });
  });

  group('AssistantResponse', () {
    test('fromMap parses answer, suggestions, and proposed items', () {
      final resp = AssistantResponse.fromMap({
        'answer': 'You have ₹5,000 outstanding.',
        'suggestions': ['Send reminder', 'Create invoice'],
        'proposed_work_items': [
          {
            'kind': 'payment_reminder',
            'customer_id': 'c1',
            'customer_name': 'Priya',
            'draft_message': 'Hi, your payment is due.',
            'priority': 'high',
          }
        ],
      });
      expect(resp.answer, 'You have ₹5,000 outstanding.');
      expect(resp.suggestions, ['Send reminder', 'Create invoice']);
      expect(resp.proposedWorkItems.length, 1);
      expect(resp.proposedWorkItems.first.kind, 'payment_reminder');
    });

    test('fromMap tolerates empty lists', () {
      final resp = AssistantResponse.fromMap({'answer': 'All good.'});
      expect(resp.suggestions, isEmpty);
      expect(resp.proposedWorkItems, isEmpty);
    });
  });

  group('AssistantTurn', () {
    test('user turn has no proposed items', () {
      final turn = AssistantTurn.user('How much is pending?');
      expect(turn.role, 'user');
      expect(turn.text, 'How much is pending?');
      expect(turn.proposedItems, isEmpty);
    });

    test('assistant turn carries proposed items', () {
      final items = [
        ProposedWorkItem.fromMap({
          'kind': 'payment_reminder',
          'customer_id': 'c1',
          'customer_name': 'Priya',
          'draft_message': 'Pay up.',
          'priority': 'high',
        }),
      ];
      final turn = AssistantTurn.assistant('Here are reminders.', proposedItems: items);
      expect(turn.role, 'assistant');
      expect(turn.proposedItems.length, 1);
    });
  });
}
