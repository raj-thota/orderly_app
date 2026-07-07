import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';

import '../controller/products_provider.dart';
import '../data/product.dart';
import '../widgets/product_image.dart';
import 'product_form_screen.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.product});

  /// Snapshot used until the live list provides a fresher row.
  final Product product;

  Product _current(WidgetRef ref) {
    final products = ref.watch(productsControllerProvider).valueOrNull;
    if (products == null) return product;
    for (final p in products) {
      if (p.id == product.id) return p;
    }
    return product;
  }

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive this piece?'),
        content: const Text(
          'It will disappear from your catalog but stays on past orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Archive',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(productsControllerProvider.notifier).archive(product.id!);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Piece archived')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = _current(ref);
    final controller = ref.read(productsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductFormScreen(existing: p),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Archive',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _confirmArchive(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          _gallery(p),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  Money.inr(p.price),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.money,
                  ),
                ),
                if ((p.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    p.description!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: p.isUnique
                      ? _pieceStatusControl(p, controller)
                      : _stockControl(p, controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gallery(Product p) {
    if (p.images.isEmpty) {
      return const SizedBox(height: 280, child: ProductImage(path: null));
    }
    return SizedBox(
      height: 340,
      child: PageView(
        children: [
          for (final path in p.images) ProductImage(path: path),
        ],
      ),
    );
  }

  Widget _pieceStatusControl(Product p, ProductsController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Availability',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'available', label: Text('Available')),
              ButtonSegment(value: 'booked', label: Text('Booked')),
              ButtonSegment(value: 'sold', label: Text('Sold')),
            ],
            selected: {p.pieceStatus},
            onSelectionChanged: (selection) {
              controller.setPieceStatus(p.id!, selection.first);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Booked reserves the piece so it cannot be sold twice.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _stockControl(Product p, ProductsController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('In stock', style: TextStyle(fontWeight: FontWeight.w700)),
        Row(
          children: [
            IconButton(
              onPressed:
                  p.qtyOnHand > 0 ? () => controller.adjustQty(p, -1) : null,
              icon: const Icon(Icons.remove_circle_outline),
              color: AppColors.primary,
            ),
            SizedBox(
              width: 40,
              child: Text(
                '${p.qtyOnHand}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: () => controller.adjustQty(p, 1),
              icon: const Icon(Icons.add_circle_outline),
              color: AppColors.primary,
            ),
          ],
        ),
      ],
    );
  }
}
