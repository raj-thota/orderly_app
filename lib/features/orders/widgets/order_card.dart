import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';
import 'package:orderly_app/shared/widgets/status_pill.dart';

import '../data/order.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final itemNames = order.items.map((i) => i.name).join(', ');
    // AppCard has no onTap; wrap it in an InkWell for the tap affordance.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  order.orderNumber != null ? '#${order.orderNumber}' : 'Order',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    order.customerName ?? 'Customer',
                    style: const TextStyle(color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  Money.inr(order.grandTotal),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text('${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: AppSpacing.sm),
                StatusPill(status: order.status),
                const SizedBox(width: AppSpacing.sm),
                StatusPill(status: order.paymentStatus),
              ],
            ),
            if (itemNames.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(itemNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
