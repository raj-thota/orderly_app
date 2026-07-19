import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/tap_deduper.dart';

void main() {
  test('null or empty payload is never handled', () {
    final d = TapDeduper();
    expect(d.shouldHandle(null), isFalse);
    expect(d.shouldHandle(''), isFalse);
  });

  test('first valid payload is handled', () {
    final d = TapDeduper();
    expect(d.shouldHandle('lead1'), isTrue);
  });

  test('same payload within the window is suppressed (launch + callback double)',
      () {
    var t = DateTime(2026, 7, 19, 10, 0, 0);
    final d = TapDeduper(window: const Duration(seconds: 2), now: () => t);
    expect(d.shouldHandle('lead1'), isTrue);
    t = t.add(const Duration(milliseconds: 300));
    expect(d.shouldHandle('lead1'), isFalse);
  });

  test('same payload after the window is handled again', () {
    var t = DateTime(2026, 7, 19, 10, 0, 0);
    final d = TapDeduper(window: const Duration(seconds: 2), now: () => t);
    expect(d.shouldHandle('lead1'), isTrue);
    t = t.add(const Duration(seconds: 3));
    expect(d.shouldHandle('lead1'), isTrue);
  });

  test('different payload within the window is handled', () {
    var t = DateTime(2026, 7, 19, 10, 0, 0);
    final d = TapDeduper(window: const Duration(seconds: 2), now: () => t);
    expect(d.shouldHandle('lead1'), isTrue);
    t = t.add(const Duration(milliseconds: 300));
    expect(d.shouldHandle('lead2'), isTrue);
  });
}
