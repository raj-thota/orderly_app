import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/data/products_service.dart';

class FakeProductsService implements ProductsService {
  FakeProductsService(List<Product> seed) : _rows = List.of(seed);

  final List<Product> _rows;
  final List<Map<String, dynamic>> updates = [];

  @override
  Future<List<Product>> fetchProducts() async => List.of(_rows);

  @override
  Future<Product> addProduct(Product product) async {
    final created =
        Product.fromMap({...product.toMap(), 'id': 'p${_rows.length + 1}'});
    _rows.add(created);
    return created;
  }

  @override
  Future<Product> updateProduct(String id, Map<String, dynamic> changes) async {
    updates.add({'id': id, ...changes});
    final index = _rows.indexWhere((p) => p.id == id);
    final merged = Product.fromMap({..._rows[index].toMap(), ...changes});
    _rows[index] = merged;
    return merged;
  }

  @override
  Future<void> archiveProduct(String id) async {
    _rows.removeWhere((p) => p.id == id);
  }

  @override
  Future<String> uploadImage(String localPath) async => 'fake/$localPath';

  @override
  Future<void> removeImages(List<String> paths) async {}

  @override
  Future<String> signedUrl(String path) async => 'https://signed/$path';
}

void main() {
  test('load exposes products from the service', () async {
    final fake = FakeProductsService(
      [const Product(id: 'p1', name: 'Saree', qtyOnHand: 1)],
    );
    final container = ProviderContainer(overrides: [
      productsServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(productsControllerProvider.notifier).load();

    expect(
      container.read(productsControllerProvider).value!.single.name,
      'Saree',
    );
  });

  test('rapid qty taps do not lose updates', () async {
    final fake = FakeProductsService(
      [const Product(id: 'p1', name: 'Kurti', qtyOnHand: 1)],
    );
    final container = ProviderContainer(overrides: [
      productsServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(productsControllerProvider.notifier);
    await controller.load();

    await Future.wait([
      controller.adjustQty('p1', 1),
      controller.adjustQty('p1', 1),
      controller.adjustQty('p1', 1),
    ]);

    expect(
      container.read(productsControllerProvider).value!.single.qtyOnHand,
      4,
    );
    expect(fake.updates.last['qty_on_hand'], 4);
  });

  test('qty never goes below zero', () async {
    final fake = FakeProductsService(
      [const Product(id: 'p1', name: 'Kurti', qtyOnHand: 1)],
    );
    final container = ProviderContainer(overrides: [
      productsServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(productsControllerProvider.notifier);
    await controller.load();
    await controller.adjustQty('p1', -5);

    expect(
      container.read(productsControllerProvider).value!.single.qtyOnHand,
      0,
    );
  });

  test('catalog state resets when the signed-in user changes', () async {
    final authEvents = StreamController<String?>();
    final services = <String?, FakeProductsService>{
      'userA': FakeProductsService(
        [const Product(id: 'a1', name: 'A piece')],
      ),
      'userB': FakeProductsService([]),
    };

    final container = ProviderContainer(overrides: [
      authUserIdProvider.overrideWith((ref) => authEvents.stream),
      productsServiceProvider.overrideWith((ref) {
        final uid = ref.watch(authUserIdProvider).valueOrNull;
        return services[uid] ?? FakeProductsService([]);
      }),
    ]);
    addTearDown(container.dispose);
    addTearDown(authEvents.close);

    authEvents.add('userA');
    await container.read(authUserIdProvider.future);
    await container.read(productsControllerProvider.notifier).load();
    expect(container.read(productsControllerProvider).value, hasLength(1));

    authEvents.add('userB');
    // Let the auth stream emit and dependents rebuild.
    await Future<void>.delayed(Duration.zero);
    await container.read(productsControllerProvider.notifier).load();
    expect(container.read(productsControllerProvider).value, isEmpty);
  });
}
