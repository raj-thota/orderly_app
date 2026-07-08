import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/quotations/data/quotation.dart';

void main() {
  const products = [
    Product(id: 'p1', name: 'Silk Saree', price: 2500),
    Product(id: 'p2', name: 'Cotton Kurti', price: 800),
  ];

  test('matchCatalog fills price and canonical name from a fuzzy match', () {
    final lines = matchCatalog(
      const [DraftItem(name: 'saree', qty: 2)],
      products,
    );
    expect(lines, hasLength(1));
    expect(lines.single.name, 'Silk Saree'); // canonical catalog name
    expect(lines.single.qty, 2);
    expect(lines.single.unitPrice, 2500); // pulled from catalog
  });

  test('matchCatalog keeps the draft price when the item already has one', () {
    final lines = matchCatalog(
      const [DraftItem(name: 'saree', qty: 1, price: 3000)],
      products,
    );
    expect(lines.single.unitPrice, 3000); // explicit price wins
  });

  test('matchCatalog leaves an unmatched item free-text at price 0', () {
    final lines = matchCatalog(
      const [DraftItem(name: 'dupatta', qty: 1)],
      products,
    );
    expect(lines.single.name, 'dupatta');
    expect(lines.single.unitPrice, 0);
  });

  test('matchCatalog does not let a 1-2 char product hijack items', () {
    // 'ar' is a substring of 'saree'; the reverse-match guard (len >= 3) must
    // suppress it so the item stays free-text instead of taking 'ar's price.
    final lines = matchCatalog(
      const [DraftItem(name: 'saree', qty: 1)],
      const [Product(id: 'x', name: 'ar', price: 50)],
    );
    expect(lines.single.name, 'saree');
    expect(lines.single.unitPrice, 0);
  });

  test('compose renders lines, total and UPI', () {
    final quote = Quotation.compose(
      businessName: 'Rekha Boutique',
      upiId: 'rekha@upi',
      upiName: 'Rekha',
      customerName: 'Priya',
      lines: const [
        QuoteLine(name: 'Silk Saree', qty: 2, unitPrice: 2500),
        QuoteLine(name: 'Blouse', qty: 1, unitPrice: 500),
      ],
    );
    expect(quote.total, 5500);
    expect(quote.message, contains('Rekha Boutique'));
    expect(quote.message, contains('Priya'));
    expect(quote.message, contains('Silk Saree x 2'));
    expect(quote.message, contains('₹5,500'));
    expect(quote.message, contains('rekha@upi'));
  });

  test('compose omits the UPI line when no UPI id is set', () {
    final quote = Quotation.compose(
      businessName: 'Shop',
      upiId: null,
      upiName: null,
      customerName: null,
      lines: const [QuoteLine(name: 'Item', qty: 1, unitPrice: 100)],
    );
    expect(quote.message.toLowerCase(), isNot(contains('upi')));
    expect(quote.total, 100);
  });
}
