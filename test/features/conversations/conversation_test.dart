import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/conversations/data/conversation.dart';

void main() {
  test('fromMap parses all fields', () {
    final c = Conversation.fromMap({
      'id': 'cv1',
      'user_id': 'u1',
      'customer_id': 'c1',
      'last_message_at': '2026-07-14T10:30:00.000Z',
      'created_at': '2026-07-01T08:00:00.000Z',
      'updated_at': '2026-07-14T10:30:00.000Z',
    });

    expect(c.id, 'cv1');
    expect(c.userId, 'u1');
    expect(c.customerId, 'c1');
    expect(c.lastMessageAt, DateTime.parse('2026-07-14T10:30:00.000Z'));
    expect(c.createdAt, DateTime.parse('2026-07-01T08:00:00.000Z'));
  });

  test('fromMap tolerates missing optional fields', () {
    final c = Conversation.fromMap({'id': 'cv2', 'customer_id': 'c2'});
    expect(c.id, 'cv2');
    expect(c.lastMessageAt, isNull);
    expect(c.createdAt, isNull);
  });

  test('fromMap reads customer name from join', () {
    final c = Conversation.fromMap({
      'id': 'cv3',
      'customer_id': 'c3',
      'customers': {'name': 'Priya Sharma', 'phone': '9876543210'},
    });
    expect(c.customerName, 'Priya Sharma');
    expect(c.customerPhone, '9876543210');
  });

  test('fromMap tolerates missing customer join', () {
    final c = Conversation.fromMap({'id': 'cv4', 'customer_id': 'c4'});
    expect(c.customerName, isNull);
    expect(c.customerPhone, isNull);
  });
}
