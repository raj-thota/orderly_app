import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/conversations/data/ai_summary.dart';

void main() {
  test('parses all fields from map', () {
    final m = {
      'id': 'sum-1',
      'user_id': 'u-1',
      'customer_id': 'c-1',
      'bullets': ['wants discount', 'budget ₹10k'],
      'close_confidence': 0.82,
      'source_hash': 'abc123',
      'created_at': '2026-07-15T10:00:00.000Z',
    };
    final s = AiSummary.fromMap(m);
    expect(s.id, 'sum-1');
    expect(s.customerId, 'c-1');
    expect(s.bullets, ['wants discount', 'budget ₹10k']);
    expect(s.closeConfidence, closeTo(0.82, 0.001));
    expect(s.sourceHash, 'abc123');
    expect(s.createdAt, isNotNull);
  });

  test('tolerates missing optional fields', () {
    final s = AiSummary.fromMap({'id': 's', 'customer_id': 'c'});
    expect(s.bullets, isEmpty);
    expect(s.closeConfidence, isNull);
    expect(s.sourceHash, isNull);
    expect(s.createdAt, isNull);
  });

  test('bullets defaults to empty list when not a list', () {
    final s = AiSummary.fromMap({'id': 's', 'customer_id': 'c', 'bullets': null});
    expect(s.bullets, isEmpty);
  });

  test('hasSummary is false when bullets empty', () {
    final s = AiSummary.fromMap({'id': 's', 'customer_id': 'c'});
    expect(s.hasSummary, isFalse);
  });

  test('hasSummary is true when bullets present', () {
    final s = AiSummary.fromMap({
      'id': 's',
      'customer_id': 'c',
      'bullets': ['prefers morning calls'],
    });
    expect(s.hasSummary, isTrue);
  });
}
