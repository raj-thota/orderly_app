import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/utils/money.dart';

void main() {
  group('Money.inr', () {
    test('formats whole rupees with symbol, no decimals', () {
      expect(Money.inr(1200), '₹1,200');
    });

    test('formats fractional rupees with two decimals', () {
      expect(Money.inr(1234.5), '₹1,234.50');
    });

    test('uses Indian digit grouping (lakhs)', () {
      expect(Money.inr(1234567), '₹12,34,567');
    });

    test('handles zero', () {
      expect(Money.inr(0), '₹0');
    });

    test('handles negatives (dues)', () {
      expect(Money.inr(-500), '-₹500');
    });

    test('can omit the symbol', () {
      expect(Money.inr(1200, symbol: false), '1,200');
    });
  });
}
