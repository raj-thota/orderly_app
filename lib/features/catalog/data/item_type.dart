import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';

/// Registry of catalog item types. Every type-aware surface (badge, placeholder,
/// filter) reads from here — adding a new type (subscription, rental, bundle …)
/// is a single entry with no widget changes.
class ItemType {
  const ItemType({
    required this.id,
    required this.label,
    required this.icon,
    required this.accent,
    required this.tint,
    required this.gradient,
  });

  final String id; // persisted db value
  final String label;
  final IconData icon;
  final Color accent; // icon + label color
  final Color tint; // badge background
  final List<Color> gradient; // placeholder background (2 stops)

  static const product = ItemType(
    id: 'product',
    label: 'Product',
    icon: Icons.inventory_2_outlined,
    accent: AppColors.typeProductAccent,
    tint: AppColors.typeProductTint,
    gradient: [AppColors.typeProductTint, AppColors.typeProductGradientEnd],
  );
  static const service = ItemType(
    id: 'service',
    label: 'Service',
    icon: Icons.handyman_outlined,
    accent: AppColors.typeServiceAccent,
    tint: AppColors.typeServiceTint,
    gradient: [AppColors.typeServiceTint, AppColors.typeServiceGradientEnd],
  );
  static const digital = ItemType(
    id: 'digital',
    label: 'Digital Product',
    icon: Icons.devices_outlined,
    accent: AppColors.typeDigitalAccent,
    tint: AppColors.typeDigitalTint,
    gradient: [AppColors.typeDigitalTint, AppColors.typeDigitalGradientEnd],
  );
  static const other = ItemType(
    id: 'other',
    label: 'Other',
    icon: Icons.category_outlined,
    accent: AppColors.typeOtherAccent,
    tint: AppColors.typeOtherTint,
    gradient: [AppColors.typeOtherTint, AppColors.typeOtherGradientEnd],
  );

  static const List<ItemType> values = [product, service, digital, other];

  static ItemType fromId(String? id) =>
      values.firstWhere((t) => t.id == id, orElse: () => other);
}
