import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

/// One settings row. Variants: default, comingSoon (disabled + chip),
/// danger (destructive, e.g. logout).
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.comingSoon = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool comingSoon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.primary;
    final enabled = !comingSoon && onTap != null;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: enabled ? color : AppColors.textSecondary, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: danger ? AppColors.danger : AppColors.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))
          : null,
      trailing: comingSoon
          ? Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text('Coming soon',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            )
          : (danger
              ? null
              : const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary)),
      onTap: enabled ? onTap : null,
    );
  }
}
