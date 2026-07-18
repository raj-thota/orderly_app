import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';

import '../controller/products_provider.dart';
import '../data/item_type.dart';
import 'item_placeholder.dart';

/// Renders a private-storage product photo via a signed URL, with a quiet
/// placeholder for missing/loading/error states.
class ProductImage extends ConsumerWidget {
  const ProductImage({
    super.key,
    this.path,
    this.iconSize = 34,
    this.cacheWidth,
    this.type,
    this.name,
  });

  final String? path;
  final double iconSize;

  /// Decode target in physical pixels — keeps grid tiles and thumbnails from
  /// decoding full-resolution photos on low-end devices.
  final int? cacheWidth;
  final ItemType? type;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = path;
    if (p == null) return _placeholder();

    final url = ref.watch(productImageUrlProvider(p));
    return url.when(
      data: (u) => Image.network(
        u,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) => _placeholder(),
      ),
      loading: () => _placeholder(),
      error: (_, _) => _placeholder(),
    );
  }

  Widget _placeholder() {
    final t = type;
    if (t != null) {
      return ItemPlaceholder(type: t, name: name ?? '', letterSize: iconSize + 6);
    }
    return Container(
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: Icon(
        Icons.photo_outlined,
        color: AppColors.textSecondary,
        size: iconSize,
      ),
    );
  }
}
