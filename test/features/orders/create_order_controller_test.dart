import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/orders/controller/create_order_provider.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';

import 'orders_controller_test.dart' show FakeOrdersService;

class _CreateFakeOrders extends FakeOrdersService {
  _CreateFakeOrders() : super(const []);
  String? lastCreatedCustomerId;
  List<CreateOrderItem>? lastCreatedItems;
  double? lastDiscount;
  double? lastShippingFee;
  String returnId = 'new-order-id';

  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<CreateOrderItem> items,
    double discount = 0,
    double shippingFee = 0,
    DateTime? expectedDate,
    String? notes,
  }) async {
    lastCreatedCustomerId = customerId;
    lastCreatedItems = items;
    lastDiscount = discount;
    lastShippingFee = shippingFee;
    return returnId;
  }
}

ProviderContainer _container(_CreateFakeOrders fake) {
  final c = ProviderContainer(overrides: [
    ordersServiceProvider.overrideWithValue(fake),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('grandTotal = subtotal − discount + shippingFee', () {
    const draft = CreateOrderDraft(
      customerId: 'c1',
      customerName: 'Priya',
      items: [
        CreateOrderItem(name: 'Ring', qty: 2, unitPrice: 5000),
        CreateOrderItem(name: 'Necklace', qty: 1, unitPrice: 8000),
      ],
      discount: 1000,
      shippingFee: 200,
    );
    expect(draft.subtotal, 18000);
    expect(draft.grandTotal, 17200);
  });

  test('grandTotal is clamped to 0 when discount exceeds subtotal + shipping', () {
    const draft = CreateOrderDraft(
      customerId: 'c1',
      customerName: 'Priya',
      items: [CreateOrderItem(name: 'Ring', qty: 1, unitPrice: 100)],
      discount: 500,
      shippingFee: 0,
    );
    expect(draft.grandTotal, 0);
  });

  test('canSubmit is false with no items', () {
    const draft = CreateOrderDraft(customerId: 'c1', customerName: 'Priya');
    expect(draft.canSubmit, isFalse);
  });

  test('canSubmit is true with at least one item and non-negative total', () {
    const draft = CreateOrderDraft(
      customerId: 'c1',
      customerName: 'Priya',
      items: [CreateOrderItem(name: 'Ring', qty: 1, unitPrice: 5000)],
    );
    expect(draft.canSubmit, isTrue);
  });

  test('addItem appends to draft items', () {
    final c = _container(_CreateFakeOrders());
    final n = c.read(createOrderProvider(('c1', 'Priya')).notifier);
    n.addItem(const CreateOrderItem(name: 'Ring', qty: 1, unitPrice: 5000));
    expect(c.read(createOrderProvider(('c1', 'Priya'))).draft.items, hasLength(1));
  });

  test('removeItem removes item at index', () {
    final c = _container(_CreateFakeOrders());
    final n = c.read(createOrderProvider(('c1', 'Priya')).notifier);
    n.addItem(const CreateOrderItem(name: 'A', qty: 1, unitPrice: 100));
    n.addItem(const CreateOrderItem(name: 'B', qty: 1, unitPrice: 200));
    n.removeItem(0);
    final items = c.read(createOrderProvider(('c1', 'Priya'))).draft.items;
    expect(items, hasLength(1));
    expect(items.first.name, 'B');
  });

  test('setDiscount updates draft discount', () {
    final c = _container(_CreateFakeOrders());
    final n = c.read(createOrderProvider(('c1', 'Priya')).notifier);
    n.setDiscount(500);
    expect(c.read(createOrderProvider(('c1', 'Priya'))).draft.discount, 500);
  });

  test('submit calls service with correct customerId and items', () async {
    final fake = _CreateFakeOrders();
    final c = _container(fake);
    final n = c.read(createOrderProvider(('c1', 'Priya')).notifier);
    n.addItem(const CreateOrderItem(name: 'Ring', qty: 2, unitPrice: 5000));
    n.setDiscount(200);
    n.setShippingFee(100);
    final id = await n.submit();
    expect(id, 'new-order-id');
    expect(fake.lastCreatedCustomerId, 'c1');
    expect(fake.lastCreatedItems, hasLength(1));
    expect(fake.lastDiscount, 200);
    expect(fake.lastShippingFee, 100);
  });

  test('submit returns null when no items', () async {
    final c = _container(_CreateFakeOrders());
    final n = c.read(createOrderProvider(('c1', 'Priya')).notifier);
    final id = await n.submit();
    expect(id, isNull);
  });
}
