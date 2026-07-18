import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

/// Label + value row with an inline edit affordance. Read mode shows label +
/// value ("Not set" when empty); edit mode swaps in a TextField.
class ProfileFieldRow extends StatelessWidget {
  const ProfileFieldRow({
    super.key,
    required this.label,
    required this.value,
    required this.isEditing,
    required this.controller,
    required this.onEdit,
    required this.onSave,
    this.keyboardType,
    this.hint,
  });

  final String label;
  final String value;
  final bool isEditing;
  final TextEditingController controller;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final TextInputType? keyboardType;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: isEditing
                ? TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: keyboardType,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      labelText: label,
                      hintText: hint,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(value.isEmpty ? 'Not set' : value,
                          style: const TextStyle(
                              fontSize: 15, color: AppColors.textPrimary)),
                    ],
                  ),
          ),
          IconButton(
            icon: Icon(isEditing ? Icons.check_rounded : Icons.edit_outlined,
                size: 18, color: AppColors.primary),
            onPressed: isEditing ? onSave : onEdit,
          ),
        ],
      ),
    );
  }
}
