import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../data/item_type.dart';

/// Soft-letter placeholder for an imageless item: pale type-tint gradient, the
/// item's first letter in the accent color, and the type icon in the corner.
class ItemPlaceholder extends StatelessWidget {
  const ItemPlaceholder({
    super.key,
    required this.type,
    required this.name,
    this.letterSize = 40,
  });

  final ItemType type;
  final String name;
  final double letterSize;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: type.gradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              letter,
              style: TextStyle(
                fontSize: letterSize,
                fontWeight: FontWeight.w800,
                color: type.accent,
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Icon(type.icon, size: 15, color: type.accent.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}
