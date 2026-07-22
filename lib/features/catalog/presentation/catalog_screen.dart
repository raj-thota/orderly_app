import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../controller/catalog_filter.dart';
import '../controller/products_provider.dart';
import '../data/item_type.dart';
import '../data/product.dart';
import '../widgets/catalog_empty_state.dart';
import '../widgets/product_tile.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';

class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsControllerProvider);
    final typeFilter = ref.watch(catalogTypeFilterProvider);
    final categoryFilter = ref.watch(catalogCategoryFilterProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                onRetry: () =>
                    ref.read(productsControllerProvider.notifier).load(),
              ),
              data: (products) {
                final categories = distinctCategories(products);
                final visible = filterProducts(products,
                    type: typeFilter, category: categoryFilter);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FilterBar(categories: categories),
                    Expanded(
                      child: products.isEmpty
                          ? CatalogEmptyState(onAdd: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen())))
                          : _grid(context, ref, visible),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, WidgetRef ref, List<Product> products) {
    return RefreshIndicator(
      onRefresh: () => ref.read(productsControllerProvider.notifier).load(),
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          96, // clears the FAB
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.72,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductTile(
            product: product,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailScreen(product: product),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Could not load your catalog.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.categories});
  final List<String> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(catalogTypeFilterProvider);
    final category = ref.watch(catalogCategoryFilterProvider);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          _chip(
            label: 'All',
            selected: type == null,
            onTap: () =>
                ref.read(catalogTypeFilterProvider.notifier).state = null,
          ),
          for (final t in ItemType.values)
            _chip(
              label: t.label,
              selected: type == t.id,
              onTap: () =>
                  ref.read(catalogTypeFilterProvider.notifier).state = t.id,
            ),
          if (categories.isNotEmpty) const SizedBox(width: AppSpacing.md),
          for (final c in categories)
            _chip(
              label: c,
              selected: category == c,
              onTap: () => ref.read(catalogCategoryFilterProvider.notifier).state =
                  category == c ? null : c,
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
