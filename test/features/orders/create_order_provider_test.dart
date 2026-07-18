import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/create_order_provider.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';

class _FakeOrdersService extends OrdersService {}

void main() {
  CreateOrderNotifier make() =>
      CreateOrderNotifier(_FakeOrdersService(), 'cust-1', 'Asha');

  test('re-adding the same product merges quantity', () {
    final n = make();
    n.addItem(const CreateOrderItem(
        name: 'Saree', unitPrice: 2499, productId: 'p1', type: 'product'));
    n.addItem(const CreateOrderItem(
        name: 'Saree', unitPrice: 2499, productId: 'p1', type: 'product'));
    expect(n.state.draft.items.length, 1);
    expect(n.state.draft.items.first.qty, 2);
  });

  test('custom items (no productId) never merge', () {
    final n = make();
    n.addItem(const CreateOrderItem(name: 'Charge', unitPrice: 100));
    n.addItem(const CreateOrderItem(name: 'Charge', unitPrice: 100));
    expect(n.state.draft.items.length, 2);
  });

  test('setQty updates a line; zero removes it', () {
    final n = make();
    n.addItem(const CreateOrderItem(name: 'A', unitPrice: 50, productId: 'p1'));
    n.setQty(0, 4);
    expect(n.state.draft.items.first.qty, 4);
    n.setQty(0, 0);
    expect(n.state.draft.items, isEmpty);
  });
}
