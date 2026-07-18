import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/product.dart';

/// Active catalog type filter (`null` = All).
final catalogTypeFilterProvider = StateProvider<String?>((_) => null);

/// Active catalog category filter (`null` = All).
final catalogCategoryFilterProvider = StateProvider<String?>((_) => null);

List<Product> filterProducts(List<Product> all, {String? type, String? category}) {
  return all.where((p) {
    if (type != null && p.type != type) return false;
    if (category != null && (p.category ?? '').trim() != category) return false;
    return true;
  }).toList();
}

List<String> distinctCategories(List<Product> all) {
  final set = <String>{};
  for (final p in all) {
    final c = p.category?.trim();
    if (c != null && c.isNotEmpty) set.add(c);
  }
  final list = set.toList()..sort();
  return list;
}
