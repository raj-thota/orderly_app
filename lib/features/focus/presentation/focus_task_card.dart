import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/focus/data/focus_action.dart';
import 'package:orderly_app/features/today/data/brief_narrative.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';
import 'package:orderly_app/features/work/data/work_item_kinds.dart';

/// A single guided-task card shown during Focus Mode.
///
/// Pure function of its inputs — no provider reads, no navigation.
/// The route (T14) wires [onPrimary], [onSkip], [onMarkDone].
class FocusTaskCard extends StatelessWidget {
  const FocusTaskCard({
    super.key,
    required this.item,
    required this.onPrimary,
    required this.onSkip,
    required this.onMarkDone,
    required this.canSkip,
  });

  final AiWorkItem item;
  final VoidCallback onPrimary;
  final VoidCallback onSkip;
  final VoidCallback onMarkDone;
  final bool canSkip;

  @override
  Widget build(BuildContext context) {
    final action = resolveFocusAction(item.kind);
    final primaryLabel = _primaryLabel(action);
    final primaryColor = _primaryColor(action);

    return Card(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kind pill
            _KindPill(kind: item.kind),
            const SizedBox(height: AppSpacing.md),
            // Title
            Text(
              focusLabel(item),
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.02 * 21,
                color: AppColors.textPrimary,
                height: 1.15,
              ),
            ),
            // "Why" line
            if ((item.context ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                item.context!,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            // Customer chip
            _CustomerChip(item: item),
            // Draft block (shown when draftMessage is present)
            if (item.draftMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              _DraftBlock(message: item.draftMessage!),
            ],
            const SizedBox(height: AppSpacing.lg),
            // Primary CTA
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                key: const Key('focus_primary'),
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(primaryLabel),
              ),
            ),
            // Sub-row: Skip / Mark done
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (canSkip)
                  TextButton(
                    key: const Key('focus_skip'),
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Skip'),
                  )
                else
                  const SizedBox.shrink(),
                TextButton(
                  onPressed: onMarkDone,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Mark done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _primaryLabel(FocusActionKind action) {
    return switch (action) {
      FocusActionKind.sendReminder => 'Send WhatsApp reminder',
      FocusActionKind.sendReply => 'Send reply',
      FocusActionKind.sendOffer => 'Send offer',
      FocusActionKind.openWorkspace => 'Open in workspace',
    };
  }

  Color _primaryColor(FocusActionKind action) {
    return switch (action) {
      FocusActionKind.sendReminder => AppColors.success,
      FocusActionKind.sendReply => AppColors.success,
      FocusActionKind.sendOffer => AppColors.success,
      FocusActionKind.openWorkspace => AppColors.primary,
    };
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _KindPill extends StatelessWidget {
  const _KindPill({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final label = kind.replaceAll('_', ' ').toUpperCase();
    final bg = _pillColor(kind);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.04 * 11,
          color: bg,
        ),
      ),
    );
  }

  Color _pillColor(String kind) {
    final group = workItemGroup(kind);
    return switch (group) {
      WorkItemGroup.collect => AppColors.danger,   // red
      WorkItemGroup.reply => AppColors.warning,    // amber
      WorkItemGroup.offer => AppColors.primary,    // indigo
      WorkItemGroup.other => AppColors.textSecondary,
    };
  }
}

class _CustomerChip extends StatelessWidget {
  const _CustomerChip({required this.item});

  final AiWorkItem item;

  @override
  Widget build(BuildContext context) {
    final name = item.customerName ?? 'Customer';
    final initials = _initials(name);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.phone != null)
                  Text(
                    item.phone!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _DraftBlock extends StatelessWidget {
  const _DraftBlock({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.aiSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                '✦',
                style: TextStyle(
                  color: AppColors.aiAccent,
                  fontSize: 12,
                ),
              ),
              SizedBox(width: AppSpacing.xs),
              Text(
                'AI DRAFT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.09 * 10,
                  color: AppColors.aiAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm - 1),
          Text(
            message,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF3B3A52),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
