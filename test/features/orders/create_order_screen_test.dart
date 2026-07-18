import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/data/products_service.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/presentation/create_order_screen.dart';

import 'orders_controller_test.dart' show FakeOrdersService;

class _ScreenFakeOrders extends FakeOrdersService {
  _ScreenFakeOrders() : super(const []);

  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<CreateOrderItem> items,
    double discount = 0,
    double shippingFee = 0,
    DateTime? expectedDate,
    String? notes,
  }) async => 'created-id';
}

/// Stub so the order builder screen can open the picker sheet in tests
/// without hitting Supabase.
class _StubProductsService implements ProductsService {
  @override
  Future<List<Product>> fetchProducts() async => const [];
  @override
  Future<Product> addProduct(Product product) async => product;
  @override
  Future<Product> updateProduct(String id, Map<String, dynamic> changes) async =>
      Product(id: id, name: '');
  @override
  Future<void> archiveProduct(String id) async {}
  @override
  Future<String> uploadImage(String localPath) async => '';
  @override
  Future<void> removeImages(List<String> paths) async {}
  @override
  Future<String> signedUrl(String path) async => '';
}

Widget _wrap({String customerId = 'c1', String customerName = 'Priya'}) {
  return ProviderScope(
    overrides: [
      ordersServiceProvider.overrideWithValue(_ScreenFakeOrders()),
      // Stub the catalog so tests don't hit Supabase.
      productsServiceProvider.overrideWithValue(_StubProductsService()),
    ],
    child: MaterialApp(
      home: CreateOrderScreen(
        customerId: customerId,
        customerName: customerName,
      ),
    ),
  );
}

void main() {
  testWidgets('shows Create Order title', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.text('Create Order'), findsWidgets);
  });

  testWidgets('shows customer name in header', (t) async {
    await t.pumpWidget(_wrap(customerName: 'Priya Sharma'));
    await t.pumpAndSettle();
    expect(find.textContaining('Priya'), findsWidgets);
  });

  testWidgets('Create button is disabled with no items', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    // Scroll to the bottom to bring the submit button into the render tree.
    await t.dragUntilVisible(
      find.byKey(const Key('create_order_submit')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await t.pumpAndSettle();
    final widget = t.widget<FilledButton>(find.byKey(const Key('create_order_submit')));
    expect(widget.onPressed, isNull);
  });

  testWidgets('Add Item button adds a row via custom item dialog', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    // Opens the picker sheet.
    await t.tap(find.text('Add Item'));
    await t.pumpAndSettle();
    // Choose custom item escape hatch.
    await t.tap(find.text('Custom item'));
    await t.pumpAndSettle();
    // Type item name in custom-item dialog.
    await t.enterText(
        find.widgetWithText(TextField, 'Item name'), 'Test Ring');
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('item_row_0')), findsOneWidget);
  });

  testWidgets('shows grand total of ₹0 initially', (t) async {
    await t.pumpWidget(_wrap());
    await t.pumpAndSettle();
    expect(find.textContaining('₹0'), findsWidgets);
  });
}
