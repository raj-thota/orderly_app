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

    test('round-trips client-owned fields through toMap/fromMap', () {
      final original = BusinessProfile(
        name: 'Sarees by Anu',
        phone: '9876543210',
        upiId: 'anu@upi',
        upiName: 'Anu',
        gstin: '29ABCDE1234F1Z5',
        defaultGstRate: 5,
      );
      final restored = BusinessProfile.fromMap(original.toMap());
      expect(restored.name, 'Sarees by Anu');
      expect(restored.upiId, 'anu@upi');
      expect(restored.defaultGstRate, 5);
      expect(restored.hasGst, isTrue);
    });

    test('fromMap tolerates missing optional fields', () {
      final p = BusinessProfile.fromMap({'name': 'X'});
      expect(p.name, 'X');
      expect(p.currency, 'INR');
      expect(p.invoicePrefix, 'INV-');
      expect(p.nextInvoiceNumber, 1);
    });

    test('fromMap reads invoice_template, defaults to classic', () {
      expect(
        BusinessProfile.fromMap({'name': 'S', 'invoice_template': 'boutique'})
            .invoiceTemplate,
        'boutique',
      );
      expect(
        BusinessProfile.fromMap({'name': 'S'}).invoiceTemplate,
        'classic',
      );
    });

    test('toMap omits server-managed numbering fields but keeps template', () {
      // invoice_prefix / next_invoice_number are owned by the DB (defaulted on
      // insert, bumped only by assign_invoice_number). The client must never
      // send them, or a plain profile re-save would reset the counter.
      final map =
          const BusinessProfile(name: 'S', invoiceTemplate: 'minimal').toMap();
      expect(map.containsKey('next_invoice_number'), isFalse);
      expect(map.containsKey('invoice_prefix'), isFalse);
      expect(map['invoice_template'], 'minimal');
    });
  });
}
