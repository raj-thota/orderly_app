import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/catalog/widgets/product_image.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';

import '../data/enquiry.dart';

class EnquiryCard extends StatelessWidget {
  const EnquiryCard({super.key, required this.enquiry, required this.onTap});

  final Enquiry enquiry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final due = enquiry.followUpDate;
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        child: Row(
          children: [
            if (enquiry.productImage != null)
              SizedBox(
                width: 52,
                height: 52,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: ProductImage(
                      path: enquiry.productImage, cacheWidth: 150),
                ),
              )
            else
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.surfaceMuted,
                child: Text(
                  (enquiry.customerName ?? 'C')[0].toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w800),
                ),
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    enquiry.customerName ?? 'Customer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  if ((enquiry.message ?? '').isNotEmpty)
                    Text(
                      enquiry.message!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                ],
              ),
            ),
            if (due != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${due.day}/${due.month}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
