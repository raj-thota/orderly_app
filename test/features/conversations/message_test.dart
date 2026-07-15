import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/conversations/data/message.dart';

void main() {
  test('fromMap parses all fields', () {
    final m = Message.fromMap({
      'id': 'm1',
      'user_id': 'u1',
      'conversation_id': 'cv1',
      'direction': 'inbound',
      'source': 'paste',
      'body': 'I want to buy a Kundan set',
      'sent_at': '2026-07-14T09:00:00.000Z',
      'meta': {'approved_work_item': 'wi1'},
      'created_at': '2026-07-14T09:00:00.000Z',
    });

    expect(m.id, 'm1');
    expect(m.conversationId, 'cv1');
    expect(m.direction, 'inbound');
    expect(m.source, 'paste');
    expect(m.body, 'I want to buy a Kundan set');
    expect(m.sentAt, DateTime.parse('2026-07-14T09:00:00.000Z'));
    expect(m.meta['approved_work_item'], 'wi1');
  });

  test('fromMap parses outbound ai_send direction and source', () {
    final m = Message.fromMap({
      'id': 'm2',
      'conversation_id': 'cv1',
      'direction': 'outbound',
      'source': 'ai_send',
      'body': 'Hi, your order is ready',
    });
    expect(m.direction, 'outbound');
    expect(m.source, 'ai_send');
    expect(m.isOutbound, isTrue);
    expect(m.isAiSend, isTrue);
  });

  test('fromMap defaults meta to empty map when absent', () {
    final m = Message.fromMap({
      'id': 'm3',
      'conversation_id': 'cv1',
      'direction': 'inbound',
      'source': 'manual',
      'body': 'Hello',
    });
    expect(m.meta, isEmpty);
  });

  test('fromMap tolerates missing sent_at', () {
    final m = Message.fromMap({
      'id': 'm4',
      'conversation_id': 'cv1',
      'direction': 'inbound',
      'source': 'manual',
      'body': 'Hello',
    });
    expect(m.sentAt, isNull);
  });

  test('isInbound is true for inbound direction', () {
    final m = Message.fromMap({
      'id': 'm5',
      'conversation_id': 'cv1',
      'direction': 'inbound',
      'source': 'manual',
      'body': 'Hi',
    });
    expect(m.isInbound, isTrue);
    expect(m.isOutbound, isFalse);
  });
}
