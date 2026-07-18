import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/data/order.dart';

void main() {
  test('OrderItem reads item_type + defaults to product', () {
    final withType = OrderItem.fromMap(
        {'name': 'Haircut', 'qty': 1, 'item_type': 'service'});
    expect(withType.type, 'service');
    expect(withType.itemType, ItemType.service);
    expect(OrderItem.fromMap({'name': 'X'}).type, 'product');
  });

  test('CreateOrderItem keeps type + imageUrl across copyWith', () {
    const item = CreateOrderItem(
        name: 'E-book', unitPrice: 199, type: 'digital', imageUrl: 'u/x.jpg');
    final bumped = item.copyWith(qty: 3);
    expect(bumped.type, 'digital');
    expect(bumped.imageUrl, 'u/x.jpg');
    expect(bumped.lineTotal, 597);
  });
}
