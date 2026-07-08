import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:orderly_app/core/providers/auth_providers.dart';
import '../data/product.dart';
import '../data/products_service.dart';

export 'package:orderly_app/core/providers/auth_providers.dart'
    show authUserIdProvider;

final productsServiceProvider = Provider<ProductsService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return ProductsService();
});

final productsControllerProvider =
    StateNotifierProvider<ProductsController, AsyncValue<List<Product>>>((ref) {
  return ProductsController(ref.watch(productsServiceProvider))..load();
});

/// Signed URL for a storage path; family-cached per path and re-signed
/// shortly before the URL would expire mid-render.
final productImageUrlProvider =
    FutureProvider.family<String, String>((ref, path) {
  final timer = Timer(
    ProductsService.signedUrlTtl - ProductsService.signedUrlRefreshMargin,
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);
  return ref.watch(productsServiceProvider).signedUrl(path);
});

class ProductsController extends StateNotifier<AsyncValue<List<Product>>> {
  ProductsController(this._service) : super(const AsyncValue.loading());

  final ProductsService _service;

  Future<void> load() async {
    state = await AsyncValue.guard(_service.fetchProducts);
  }

  Future<void> addProduct(Product product) async {
    await _service.addProduct(product);
    await load();
  }

  Future<void> updateProduct(String id, Map<String, dynamic> changes) async {
    await _service.updateProduct(id, changes);
    await load();
  }

  Future<void> setPieceStatus(String id, String status) =>
      updateProduct(id, {'piece_status': status});

  Future<void> adjustQty(String id, int delta) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final index = current.indexWhere((p) => p.id == id);
    if (index == -1) return;

    final next = current[index].qtyOnHand + delta;
    final clamped = next < 0 ? 0 : next;

    // Optimistic: rapid taps read the updated count, not a stale snapshot.
    final updated = List.of(current);
    updated[index] = updated[index].copyWith(qtyOnHand: clamped);
    state = AsyncValue.data(updated);

    try {
      await _service.updateProduct(id, {'qty_on_hand': clamped});
    } catch (e) {
      await load(); // roll back to server truth
      rethrow;
    }
  }

  Future<void> archive(String id) async {
    await _service.archiveProduct(id);
    await load();
  }
}
