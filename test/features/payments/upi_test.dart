import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/payments/data/upi.dart';

void main() {
  test('buildUpiUri composes pa, am, cu and encodes name/note', () {
    final uri = buildUpiUri(
      vpa: 'rekha@upi',
      name: 'Rekha Boutique',
      amount: 2500,
      note: 'Order #1042',
    );
    expect(uri, startsWith('upi://pay?'));
    expect(uri, contains('pa=rekha@upi'));
    expect(uri, contains('am=2500.00'));
    expect(uri, contains('cu=INR'));
    expect(uri, contains('pn=Rekha%20Boutique'));
    expect(uri, contains('tn=Order%20%231042'));
  });

  test('buildUpiUri omits pn and tn when absent', () {
    final uri = buildUpiUri(vpa: 'x@upi', amount: 100);
    expect(uri, contains('pa=x@upi'));
    expect(uri, contains('am=100.00'));
    expect(uri, isNot(contains('pn=')));
    expect(uri, isNot(contains('tn=')));
  });
}
