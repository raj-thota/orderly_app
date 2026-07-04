import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';

void main() {
  group('BusinessProfile', () {
    test('hasGst is true only when gstin is non-empty', () {
      expect(
        BusinessProfile(name: 'Shop', gstin: '29ABCDE1234F1Z5').hasGst,
        isTrue,
      );
      expect(BusinessProfile(name: 'Shop', gstin: '').hasGst, isFalse);
      expect(BusinessProfile(name: 'Shop', gstin: null).hasGst, isFalse);
    });

    test('round-trips through toMap/fromMap', () {
      final original = BusinessProfile(
        name: 'Sarees by Anu',
        phone: '9876543210',
        upiId: 'anu@upi',
        upiName: 'Anu',
        gstin: '29ABCDE1234F1Z5',
        defaultGstRate: 5,
        invoicePrefix: 'ANU-',
        nextInvoiceNumber: 42,
      );
      final restored = BusinessProfile.fromMap(original.toMap());
      expect(restored.name, 'Sarees by Anu');
      expect(restored.upiId, 'anu@upi');
      expect(restored.defaultGstRate, 5);
      expect(restored.nextInvoiceNumber, 42);
      expect(restored.hasGst, isTrue);
    });

    test('fromMap tolerates missing optional fields', () {
      final p = BusinessProfile.fromMap({'name': 'X'});
      expect(p.name, 'X');
      expect(p.currency, 'INR');
      expect(p.invoicePrefix, 'INV-');
      expect(p.nextInvoiceNumber, 1);
    });
  });
}
