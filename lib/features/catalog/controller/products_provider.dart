import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/product.dart';
import '../data/products_service.dart';

/// Signed-in user id. Catalog providers watch this so every piece of cached
/// state (product list, signed URLs) is dropped when the account changes —
/// otherwise user A's catalog would survive logout and show to user B.
final authUserIdProvider = StreamProvider<String?>((ref) {
  final auth = Supabase.instance.client.auth;
  return auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();
});

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
