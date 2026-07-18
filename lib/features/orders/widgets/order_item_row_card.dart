import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';
import 'package:orderly_app/features/catalog/widgets/product_image.dart';
import 'package:orderly_app/features/catalog/widgets/type_badge.dart';

/// One selected item in the order builder (editable) or order detail (read-only).
/// Editable when both [onQtyChanged] and [onRemove] are provided.
class OrderItemRowCard extends StatelessWidget {
  const OrderItemRowCard({
    super.key,
    required this.name,
    required this.type,
    required this.imagePath,
    required this.unitPrice,
    required this.qty,
    this.onQtyChanged,
    this.onRemove,
  });

  final String name;
  final ItemType type;
  final String? imagePath;
  final double unitPrice;
  final int qty;
  final ValueChanged<int>? onQtyChanged;
  final VoidCallback? onRemove;

  bool get _editable => onQtyChanged != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 52,
              height: 52,
              child: ProductImage(
                path: imagePath,
                type: type,
                name: name,
                iconSize: 18,
                cacheWidth: 160,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                TypeBadge(type: type, compact: false),
                const SizedBox(height: 2),
                Text('${Money.inr(unitPrice)} each',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_editable)
                _Stepper(qty: qty, onChanged: onQtyChanged!)
              else
                Text('× $qty',
                    style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(Money.inr(unitPrice * qty),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
          if (_editable && onRemove != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: AppColors.textSecondary,
              onPressed: onRemove,
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.qty, required this.onChanged});
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.remove, () => onChanged(qty - 1)),
          SizedBox(
            width: 24,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          _btn(Icons.add, () => onChanged(qty + 1)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
      );
}
