import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/ai_parse_service.dart';

void main() {
  AiParseService withJson(Map<String, dynamic>? json, {Duration? delay}) {
    return AiParseService(
      timeout: const Duration(milliseconds: 100),
      invoker: (text) async {
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
      'follow_up_date': '2026-07-10',
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
    expect(ai.followUpDate, DateTime(2026, 7, 10));
    expect(ai.confidence, 0.9);
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
}
