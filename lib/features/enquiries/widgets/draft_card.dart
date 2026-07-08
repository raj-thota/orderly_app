import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';

import '../data/capture_draft.dart';

/// Live parse result. Rows are tappable so every parsed field is correctable.
class DraftCard extends StatelessWidget {
  const DraftCard({
    super.key,
    required this.draft,
    required this.attachedProductName,
    required this.onEditName,
    required this.onEditPhone,
    required this.onEditFollowUp,
    required this.onRemoveItem,
  });

  final CaptureDraft draft;
  final String? attachedProductName;
  final VoidCallback onEditName;
  final VoidCallback onEditPhone;
  final VoidCallback onEditFollowUp;
  final void Function(int index) onRemoveItem;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                draft.type == 'order' ? 'Order draft' : 'Enquiry draft',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _row(Icons.person_outline, draft.name ?? 'Customer',
              onTap: onEditName, key: const Key('draft-name')),
          _row(Icons.phone_outlined, draft.phone ?? 'Add phone',
              muted: draft.phone == null,
              onTap: onEditPhone,
              key: const Key('draft-phone')),
          if (attachedProductName != null)
            _row(Icons.storefront_outlined, attachedProductName!),
          for (var i = 0; i < draft.items.length; i++)
            _row(
              Icons.shopping_bag_outlined,
              '${draft.items[i].qty} × ${draft.items[i].name}'
              '${draft.items[i].price != null ? ' @ ${Money.inr(draft.items[i].price!)}' : ''}',
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => onRemoveItem(i),
              ),
            ),
          _row(
            Icons.event_outlined,
            draft.followUpDate == null
                ? 'No follow-up'
                : 'Follow up ${draft.followUpDate!.day}/${draft.followUpDate!.month}',
            muted: draft.followUpDate == null,
            onTap: onEditFollowUp,
            key: const Key('draft-followup'),
          ),
        ],
      ),
    );
  }

  Widget _row(
    IconData icon,
    String text, {
    bool muted = false,
    VoidCallback? onTap,
    Widget? trailing,
    Key? key,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color:
                      muted ? AppColors.textSecondary : AppColors.textPrimary,
                  fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
