import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

class StatusPillStyle {
  const StatusPillStyle(this.label, this.color);
  final String label;
  final Color color;

  static StatusPillStyle forStatus(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return const StatusPillStyle('Available', AppColors.success);
      case 'booked':
        return const StatusPillStyle('Booked', AppColors.warning);
      case 'sold':
        return const StatusPillStyle('Sold', AppColors.textSecondary);
      case 'paid':
        return const StatusPillStyle('Paid', AppColors.success);
      case 'partial':
        return const StatusPillStyle('Partial', AppColors.warning);
      case 'unpaid':
        return const StatusPillStyle('Unpaid', AppColors.danger);
      case 'confirmed':
        return const StatusPillStyle('Confirmed', AppColors.warning);
      case 'cancelled':
        return const StatusPillStyle('Cancelled', AppColors.danger);
      case 'packed':
        return const StatusPillStyle('Packed', AppColors.info);
      case 'shipped':
        return const StatusPillStyle('Shipped', AppColors.info);
      case 'delivered':
        return const StatusPillStyle('Delivered', AppColors.success);
      default:
        final label = status.isEmpty
            ? '—'
            : status[0].toUpperCase() + status.substring(1);
        return StatusPillStyle(label, AppColors.textSecondary);
    }
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final style = StatusPillStyle.forStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
