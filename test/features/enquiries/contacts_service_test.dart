import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/contacts_service.dart';

void main() {
  group('contactToPrefill', () {
    test('trims the name and normalizes an Indian mobile with +91', () {
      final pick = contactToPrefill('  Rahul Sharma ', '+91 98765 43210');
      expect(pick.name, 'Rahul Sharma');
      expect(pick.phone, '9876543210');
    });

    test('strips a leading trunk zero and separators', () {
      final pick = contactToPrefill('Anita', '098765-43210');
      expect(pick.phone, '9876543210');
    });

    test('blank name becomes null so it never lands as an empty customer', () {
      final pick = contactToPrefill('   ', '9876543210');
      expect(pick.name, isNull);
      expect(pick.phone, '9876543210');
    });

    test('missing phone becomes null', () {
      final pick = contactToPrefill('Rahul', null);
      expect(pick.name, 'Rahul');
      expect(pick.phone, isNull);
    });
  });
}
