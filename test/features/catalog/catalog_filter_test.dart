import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/controller/catalog_filter.dart';
import 'package:orderly_app/features/catalog/data/product.dart';

void main() {
  final products = [
    Product(name: 'Saree', type: 'product', category: 'Sarees'),
    Product(name: 'Haircut', type: 'service', category: 'Salon'),
    Product(name: 'Facial', type: 'service', category: 'Salon'),
    Product(name: 'E-book', type: 'digital'),
  ];

  test('filterProducts by type', () {
    final r = filterProducts(products, type: 'service');
    expect(r.map((p) => p.name), ['Haircut', 'Facial']);
  });

  test('filterProducts by category', () {
    final r = filterProducts(products, category: 'Sarees');
    expect(r.map((p) => p.name), ['Saree']);
  });

  test('filterProducts with no filters returns all', () {
    expect(filterProducts(products).length, 4);
  });

  test('distinctCategories are sorted + de-duped, blanks dropped', () {
    expect(distinctCategories(products), ['Salon', 'Sarees']);
  });
}
