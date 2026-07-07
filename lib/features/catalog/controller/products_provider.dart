import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/product.dart';
import '../data/products_service.dart';

final productsServiceProvider =
    Provider<ProductsService>((ref) => ProductsService());

final productsControllerProvider =
    StateNotifierProvider<ProductsController, AsyncValue<List<Product>>>((ref) {
  return ProductsController(ref.watch(productsServiceProvider))..load();
});

/// Signed URL for a storage path; family-cached per path.
final productImageUrlProvider =
    FutureProvider.family<String, String>((ref, path) {
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

  Future<void> adjustQty(Product product, int delta) {
    final next = product.qtyOnHand + delta;
    return updateProduct(product.id!, {'qty_on_hand': next < 0 ? 0 : next});
  }

  Future<void> archive(String id) async {
    await _service.archiveProduct(id);
    await load();
  }
}
