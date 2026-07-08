import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/ai_parse_service.dart';

void main() {
  Map<String, dynamic>? lastBody;
  AiParseService withJson(Map<String, dynamic>? json, {Duration? delay}) {
    return AiParseService(
      timeout: const Duration(milliseconds: 100),
      invoker: (body) async {
        lastBody = body;
        if (delay != null) await Future.delayed(delay);
        return json;
      },
    );
  }

  test('coerces a well-formed AI response', () async {
    final ai = await withJson({
      'customer_name': ' Priya ',
      'phone': '+91 98765 43210',
      'items': [
        {'name': 'Saree', 'qty': 2, 'price': 1500},
        {'name': 'Kurti', 'qty': 0, 'price': null},
      ],
      'intent': 'order',
      'type': 'order',
      'follow_up_date': '2030-01-15',
      'confidence': 0.9,
    }).refine('order 2 sarees');

    expect(ai, isNotNull);
    expect(ai!.name, 'Priya');
    expect(ai.phone, '9876543210');
    expect(ai.items, hasLength(2));
    expect(ai.items![0].name, 'Saree');
    expect(ai.items![0].qty, 2);
    expect(ai.items![0].price, 1500);
    expect(ai.items![1].qty, 1); // clamped up from 0
    expect(ai.intent, 'order');
    expect(ai.type, 'order');
    expect(ai.followUpDate, DateTime(2030, 1, 15));
    expect(ai.confidence, 0.9);
  });

  test('rejects a numeric string that is not a 10-digit mobile', () async {
    final ai = await withJson({'phone': '12345', 'confidence': 0.5}).refine('x');
    expect(ai!.phone, isNull);
  });

  test('accepts a valid mobile carrying a country code', () async {
    final ai =
        await withJson({'phone': '919876543210', 'confidence': 0.5}).refine('x');
    expect(ai!.phone, '9876543210');
  });

  test('drops a follow-up date in the past', () async {
    final ai = await withJson(
        {'follow_up_date': '2000-01-01', 'confidence': 0.5}).refine('x');
    expect(ai!.followUpDate, isNull);
  });

  test('rejects out-of-whitelist intent/type and bad date', () async {
    final ai = await withJson({
      'customer_name': '',
      'phone': 'not-a-phone',
      'items': null,
      'intent': 'garbage',
      'type': 'weird',
      'follow_up_date': 'soon',
      'confidence': 5,
    }).refine('x');

    expect(ai, isNotNull);
    expect(ai!.name, isNull);
    expect(ai.phone, isNull);
    expect(ai.items, isNull);
    expect(ai.intent, isNull);
    expect(ai.type, isNull);
    expect(ai.followUpDate, isNull);
    expect(ai.confidence, 1.0); // clamped to 0..1
  });

  test('returns null when the transport yields null', () async {
    expect(await withJson(null).refine('x'), isNull);
  });

  test('returns null on timeout', () async {
    final svc = withJson({'confidence': 0.5},
        delay: const Duration(milliseconds: 500));
    expect(await svc.refine('x'), isNull);
  });

  test('returns null when the transport throws', () async {
    final svc = AiParseService(
      timeout: const Duration(seconds: 1),
      invoker: (_) async => throw Exception('boom'),
    );
    expect(await svc.refine('x'), isNull);
  });

  test('forwards the text in the request body', () async {
    await withJson({'confidence': 0.5}).refine('order 2 sarees');
    expect(lastBody!['text'], 'order 2 sarees');
    expect(lastBody!.containsKey('image'), isFalse);
  });

  test('base64-encodes an attached image into the body', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await withJson({'confidence': 0.5})
        .refine('', image: bytes, mime: 'image/png');
    final image = lastBody!['image'] as Map<String, dynamic>;
    expect(image['mime'], 'image/png');
    expect(image['data'], base64Encode(bytes));
  });
}
