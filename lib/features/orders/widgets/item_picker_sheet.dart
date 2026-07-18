import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/catalog/controller/catalog_filter.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/widgets/item_placeholder.dart';
import 'package:orderly_app/features/catalog/widgets/type_badge.dart';

/// Bottom-sheet catalog picker for the order builder: search + type + category
/// filters over an image-tile grid, plus a custom-item escape hatch.
class ItemPickerSheet extends StatefulWidget {
  const ItemPickerSheet({
    super.key,
    required this.products,
    required this.onPick,
    required this.onCustom,
  });

  final List<Product> products;
  final ValueChanged<Product> onPick;
  final VoidCallback onCustom;

  @override
  State<ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<ItemPickerSheet> {
  String _query = '';
  String? _type;
  String? _category;

  @override
  Widget build(BuildContext context) {
    final categories = distinctCategories(widget.products);
    var visible =
        filterProducts(widget.products, type: _type, category: _category);
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      visible =
          visible.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Add item',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                TextButton.icon(
                  onPressed: widget.onCustom,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Custom item'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search items',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('All', _type == null,
                      () => setState(() => _type = null)),
                  for (final t in ItemType.values)
                    _chip(t.label, _type == t.id,
                        () => setState(() => _type = t.id)),
                  if (categories.isNotEmpty)
                    const SizedBox(width: AppSpacing.md),
                  for (final c in categories)
                    _chip(
                        c,
                        _category == c,
                        () => setState(
                            () => _category = _category == c ? null : c)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Text('No matching items',
                          style:
                              TextStyle(color: AppColors.textSecondary)))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: AppSpacing.md,
                        crossAxisSpacing: AppSpacing.md,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, i) => _tile(context, visible[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _tile(BuildContext context, Product p) {
    return GestureDetector(
      onTap: () => widget.onPick(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: _productImage(p),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: TypeBadge(type: p.itemType, compact: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          Text(Money.inr(p.price),
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  /// Renders the product thumbnail. Uses [ItemPlaceholder] when there is no
  /// cover image so the widget tree stays Riverpod-free (no ConsumerWidget
  /// needed for signed-URL resolution at this level).
  Widget _productImage(Product p) {
    final cover = p.coverImage;
    if (cover == null) {
      return ItemPlaceholder(type: p.itemType, name: p.name, letterSize: 28);
    }
    return Image.network(
      cover,
      fit: BoxFit.cover,
      cacheWidth: 240,
      errorBuilder: (_, _, _) =>
          ItemPlaceholder(type: p.itemType, name: p.name, letterSize: 28),
    );
  }
}
