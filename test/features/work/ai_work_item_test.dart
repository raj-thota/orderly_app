import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

void main() {
  test('fromMap parses all fields', () {
    final item = AiWorkItem.fromMap({
      'id': 'wi1',
      'user_id': 'u1',
      'customer_id': 'c1',
      'lead_id': 'l1',
      'order_id': 'o1',
      'kind': 'payment_reminder',
      'priority': 'high',
      'score': 95,
      'title': 'Payment pending',
      'context': 'Rahul owes ₹12,000',
      'amount': '12000.00',
      'draft': {'message': 'Hi Rahul, your payment of ₹12,000 is due.'},
      'confidence': '0.92',
      'status': 'pending',
      'batch_id': 'b1',
      'expires_at': '2026-07-16T00:00:00.000Z',
      'created_at': '2026-07-14T08:00:00.000Z',
    });

    expect(item.id, 'wi1');
    expect(item.customerId, 'c1');
    expect(item.leadId, 'l1');
    expect(item.orderId, 'o1');
    expect(item.kind, 'payment_reminder');
    expect(item.priority, 'high');
    expect(item.score, 95);
    expect(item.title, 'Payment pending');
    expect(item.context, 'Rahul owes ₹12,000');
    expect(item.amount, 12000.0);
    expect(item.draftMessage, 'Hi Rahul, your payment of ₹12,000 is due.');
    expect(item.confidence, closeTo(0.92, 0.001));
    expect(item.status, 'pending');
    expect(item.batchId, 'b1');
    expect(item.expiresAt, DateTime.parse('2026-07-16T00:00:00.000Z'));
  });

  test('fromMap defaults status to pending', () {
    final item = AiWorkItem.fromMap({
      'id': 'wi2',
      'kind': 'reply',
      'priority': 'low',
      'score': 10,
      'title': 'Reply to Meena',
      'batch_id': 'b1',
    });
    expect(item.status, 'pending');
  });

  test('fromMap tolerates missing optional fields', () {
    final item = AiWorkItem.fromMap({
      'id': 'wi3',
      'kind': 'invoice',
      'priority': 'medium',
      'score': 50,
      'title': 'Send invoice',
      'batch_id': 'b2',
    });
    expect(item.customerId, isNull);
    expect(item.leadId, isNull);
    expect(item.orderId, isNull);
    expect(item.amount, isNull);
    expect(item.confidence, isNull);
    expect(item.context, isNull);
    expect(item.draftMessage, isNull);
    expect(item.expiresAt, isNull);
  });

  test('isPending returns true only for pending status', () {
    final pending = AiWorkItem.fromMap({
      'id': 'wi4', 'kind': 'reply', 'priority': 'low',
      'score': 0, 'title': 'T', 'batch_id': 'b1', 'status': 'pending',
    });
    final done = AiWorkItem.fromMap({
      'id': 'wi5', 'kind': 'reply', 'priority': 'low',
      'score': 0, 'title': 'T', 'batch_id': 'b1', 'status': 'done',
    });
    expect(pending.isPending, isTrue);
    expect(done.isPending, isFalse);
  });

  test('isHigh/isMedium/isLow map priority string', () {
    AiWorkItem make(String p) => AiWorkItem.fromMap({
      'id': 'wi6', 'kind': 'reply', 'priority': p,
      'score': 0, 'title': 'T', 'batch_id': 'b1',
    });
    expect(make('high').isHigh, isTrue);
    expect(make('medium').isMedium, isTrue);
    expect(make('low').isLow, isTrue);
    expect(make('high').isMedium, isFalse);
  });

  test('fromMap reads customer name from join', () {
    final item = AiWorkItem.fromMap({
      'id': 'wi7',
      'kind': 'reply',
      'priority': 'high',
      'score': 80,
      'title': 'Reply to Priya',
      'batch_id': 'b1',
      'customers': {'name': 'Priya Sharma'},
    });
    expect(item.customerName, 'Priya Sharma');
  });
}
