import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';

void main() {
  test('buildItemsPayload includes item_type + image_url snapshot', () {
    final payload = buildItemsPayload([
      const CreateOrderItem(
          name: 'Saree',
          unitPrice: 2499,
          qty: 2,
          productId: 'p1',
          type: 'product',
          imageUrl: 'u/1.jpg'),
      const CreateOrderItem(name: 'Charge', unitPrice: 100), // custom
    ]);
    expect(payload[0]['item_type'], 'product');
    expect(payload[0]['image_url'], 'u/1.jpg');
    expect(payload[0]['product_id'], 'p1');
    expect(payload[1].containsKey('product_id'), isFalse);
    expect(payload[1].containsKey('image_url'), isFalse);
    expect(payload[1]['item_type'], 'product');
  });
}
