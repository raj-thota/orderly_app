import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../data/item_type.dart';

/// Soft-tint pill for an item type: tinted background, accent icon + label.
class TypeBadge extends StatelessWidget {
  const TypeBadge({super.key, required this.type, this.compact = false});

  final ItemType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: type.tint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 12, color: type.accent),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              type.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: type.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
