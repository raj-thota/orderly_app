import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

class AiCard extends StatelessWidget {
  const AiCard({
    super.key,
    required this.title,
    required this.child,
    this.onEdit,
  });

  final String title;
  final Widget child;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.aiSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.aiAccent.withAlpha(60)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: AppColors.aiAccent),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.aiAccent,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.aiAccent),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
