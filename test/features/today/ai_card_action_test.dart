import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/today/data/ai_card_action.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _item({
  String kind = 'payment_reminder',
  String? phone,
  String? draftMessage,
}) =>
    AiWorkItem(
      id: '1',
      kind: kind,
      priority: 'high',
      score: 90,
      title: 'T',
      status: 'pending',
      batchId: 'b1',
      customerId: 'c1',
      customerName: 'Priya',
      phone: phone,
      draftMessage: draftMessage,
    );

void main() {
  test('follow_up with phone resolves to a phone call', () {
    final action = resolveAiCardAction(_item(kind: 'follow_up', phone: '9876543210'));
    expect(action.type, AiCardActionType.call);
    expect(action.uri.toString(), 'tel:9876543210');
  });

  test('call kind with phone resolves to a phone call', () {
    final action = resolveAiCardAction(_item(kind: 'call', phone: '9876543210'));
    expect(action.type, AiCardActionType.call);
  });

  test('payment_reminder with phone resolves to WhatsApp', () {
    final action =
        resolveAiCardAction(_item(kind: 'payment_reminder', phone: '9876543210'));
    expect(action.type, AiCardActionType.whatsapp);
    expect(action.uri!.host, 'wa.me');
    expect(action.uri!.path, '/919876543210');
  });

  test('reply/default kind with phone resolves to WhatsApp', () {
    final action = resolveAiCardAction(_item(kind: 'reply', phone: '9876543210'));
    expect(action.type, AiCardActionType.whatsapp);
  });

  test('WhatsApp prefills the draft message when present', () {
    final action = resolveAiCardAction(
        _item(kind: 'payment_reminder', phone: '9876543210', draftMessage: 'Hi Priya'));
    expect(action.uri!.queryParameters['text'], 'Hi Priya');
  });

  test('WhatsApp omits text when no draft message', () {
    final action =
        resolveAiCardAction(_item(kind: 'payment_reminder', phone: '9876543210'));
    expect(action.uri!.query, isEmpty);
  });

  test('offer kind resolves to workspace (no launchable URL)', () {
    final action = resolveAiCardAction(_item(kind: 'offer', phone: '9876543210'));
    expect(action.type, AiCardActionType.workspace);
    expect(action.uri, isNull);
  });

  test('share_catalog kind resolves to workspace', () {
    final action =
        resolveAiCardAction(_item(kind: 'share_catalog', phone: '9876543210'));
    expect(action.type, AiCardActionType.workspace);
  });

  test('missing phone always resolves to workspace', () {
    expect(resolveAiCardAction(_item(kind: 'payment_reminder')).type,
        AiCardActionType.workspace);
    expect(resolveAiCardAction(_item(kind: 'follow_up')).type,
        AiCardActionType.workspace);
  });

  test('empty phone resolves to workspace', () {
    expect(resolveAiCardAction(_item(kind: 'call', phone: '')).type,
        AiCardActionType.workspace);
  });

  test('already country-coded phone is not double-prefixed for WhatsApp', () {
    final action =
        resolveAiCardAction(_item(kind: 'payment_reminder', phone: '919876543210'));
    expect(action.uri!.path, '/919876543210');
  });

  test('phone with spaces and punctuation is normalized to digits', () {
    final action = resolveAiCardAction(
        _item(kind: 'payment_reminder', phone: '+91 98765-43210'));
    expect(action.uri!.path, '/919876543210');
  });
}
