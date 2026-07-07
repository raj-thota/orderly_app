import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';

void main() {
  group('Product', () {
    test('round-trips through toMap/fromMap', () {
      final original = Product(
        name: 'Banarasi Silk Saree',
        description: 'Deep red, gold zari border',
        price: 4500,
        images: ['uid/1.jpg', 'uid/2.jpg'],
        isUnique: true,
        pieceStatus: 'booked',
      );
      final restored = Product.fromMap(original.toMap());
      expect(restored.name, 'Banarasi Silk Saree');
      expect(restored.description, 'Deep red, gold zari border');
      expect(restored.price, 4500);
      expect(restored.images, ['uid/1.jpg', 'uid/2.jpg']);
      expect(restored.isUnique, isTrue);
      expect(restored.pieceStatus, 'booked');
    });

    test('fromMap tolerates missing optional fields', () {
      final p = Product.fromMap({'name': 'Cotton Kurti'});
      expect(p.name, 'Cotton Kurti');
      expect(p.images, isEmpty);
      expect(p.price, 0);
      expect(p.unit, 'pc');
      expect(p.isUnique, isFalse);
      expect(p.pieceStatus, 'available');
      expect(p.qtyOnHand, 0);
      expect(p.active, isTrue);
    });

    test('fromMap parses numeric strings from Postgres', () {
      final p = Product.fromMap(
        {'name': 'X', 'price': '1499.50', 'qty_on_hand': '3'},
      );
      expect(p.price, 1499.50);
      expect(p.qtyOnHand, 3);
    });

    test('unique piece availability follows piece_status', () {
      expect(
        Product(name: 'A', isUnique: true, pieceStatus: 'available')
            .isAvailable,
        isTrue,
      );
      expect(
        Product(name: 'A', isUnique: true, pieceStatus: 'booked').isAvailable,
        isFalse,
      );
      expect(
        Product(name: 'A', isUnique: true, pieceStatus: 'sold').isAvailable,
        isFalse,
      );
    });

    test('stocked availability follows qty_on_hand', () {
      expect(Product(name: 'A', qtyOnHand: 2).isAvailable, isTrue);
      expect(Product(name: 'A', qtyOnHand: 0).isAvailable, isFalse);
    });

    test('coverImage is first image or null', () {
      expect(Product(name: 'A', images: ['u/a.jpg']).coverImage, 'u/a.jpg');
      expect(Product(name: 'A').coverImage, isNull);
    });
  });
}
