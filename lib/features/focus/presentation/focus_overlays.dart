import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/focus/presentation/orbit.dart';

// Grip handle width (per design: 38dp)
const double _kGripWidth = 38;

// ---------------------------------------------------------------------------
// Exit Dialog
// ---------------------------------------------------------------------------

/// Shows a centered modal dialog asking the user whether to leave Focus Mode.
///
/// Returns `true` when the user taps "Leave", `false` when they tap "Keep
/// going" or dismiss the dialog via the barrier.
Future<bool> showFocusExitDialog(
  BuildContext context, {
  required int done,
  required int total,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _FocusExitDialog(done: done, total: total),
  );
  return result ?? false;
}

class _FocusExitDialog extends StatelessWidget {
  const _FocusExitDialog({required this.done, required this.total})
      : assert(done <= total, 'done ($done) must not exceed total ($total)');

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      backgroundColor: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Static Orbit in dialogs: disableAnimations so pumpAndSettle
            // settles in tests and to reduce visual noise in interruption contexts.
            MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Orbit(mood: OrbitMood.neutral, size: 70),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Leave Focus Mode?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    // letterSpacing in logical px; -0.44 ≈ -0.02 × 22sp (titleLarge)
                    letterSpacing: -0.44,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "You've done $done of $total — I'll save your progress so you can pick up right here anytime.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(
                        color: AppColors.border,
                        width: 1.5,
                      ),
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text(
                      'Leave',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.surface,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text(
                      'Keep going',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skip Bottom Sheet
// ---------------------------------------------------------------------------

/// Shows a modal bottom sheet asking the user whether to skip the current task.
///
/// Returns `true` when the user taps "Skip →", `false` when they tap "Keep
/// task" or dismiss the sheet via the barrier.
Future<bool> showFocusSkipSheet(
  BuildContext context, {
  required String customerName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.xl + AppSpacing.xs),
      ),
    ),
    builder: (ctx) => _FocusSkipSheet(customerName: customerName),
  );
  return result ?? false;
}

class _FocusSkipSheet extends StatelessWidget {
  const _FocusSkipSheet({required this.customerName});

  final String customerName;

  @override
  Widget build(BuildContext context) {
    // viewInsets.bottom accounts for the soft keyboard pushing sheet content up.
    final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg + AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.lg + AppSpacing.xs,
        AppSpacing.xl + keyboardBottom + safeBottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grip handle
          Container(
            width: _kGripWidth,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const Orbit(mood: OrbitMood.thinking, size: 64),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Skip this for now?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.44,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "No problem. I'll bring $customerName's task back at the end of your session.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(
                      color: AppColors.border,
                      width: 1.5,
                    ),
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: const Text(
                    'Keep task',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surface,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: const Text(
                    'Skip →',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error Toast (inline widget — the route places this, not navigation)
// ---------------------------------------------------------------------------

/// An inline error card with a red left border for failed send actions.
///
/// This is a pure widget — no navigation or dialogs. The route is responsible
/// for placing it in the widget tree (e.g. inside a Stack above the task card).
///
/// Also exported as a top-level function [focusErrorToast] for callers that
/// prefer a function-call API.
class FocusErrorToast extends StatelessWidget {
  const FocusErrorToast({
    super.key,
    required this.customerName,
    required this.onRetry,
  });

  final String customerName;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: const Border(
            left: BorderSide(color: AppColors.danger, width: 4),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md + AppSpacing.xs,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Couldn\'t send to $customerName',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Network hiccup — your draft is safe.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Try again',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience function that returns a [FocusErrorToast] widget.
///
/// Kept for callers that use the function-call style from the spec API.
Widget focusErrorToast({
  required String customerName,
  required VoidCallback onRetry,
}) =>
    FocusErrorToast(customerName: customerName, onRetry: onRetry);
