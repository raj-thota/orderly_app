import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/account_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/features/auth/controller/auth_controller.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';

/// Confirms, signs out, and clears cached business data. Navigation happens
/// reactively via RootGate watching authProvider — no imperative push here.
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text(
        'You will need to sign in again to access your shop.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Log out',
            style: TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  await ref.read(authProvider.notifier).logout();

  // Clear cached business data so the next account starts clean.
  ref.invalidate(userProfileProvider);
  ref.invalidate(businessProfileProvider);

  // RootGate (the first route) decides WHAT to show based on auth state; pop any
  // pushed screens (Settings/Profile) so that reactive root becomes visible.
  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

/// Permanently deletes the account and all data. Because this is irreversible,
/// the user must type DELETE to confirm (guards against accidental taps).
/// Required by App Store 5.1.1(v) and Google Play. On success the user is
/// signed out and RootGate reactively shows the intro.
Future<void> confirmAndDeleteAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  final typed = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setInner) {
        final canDelete = typed.text.trim().toUpperCase() == 'DELETE';
        return AlertDialog(
          title: const Text('Delete account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently deletes your account and all your data — '
                'customers, orders, invoices, and settings. This cannot be undone.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Type DELETE to confirm.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: typed,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setInner(() {}),
                decoration: const InputDecoration(
                  hintText: 'DELETE',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: canDelete ? () => Navigator.pop(ctx, true) : null,
              child: Text(
                'Delete',
                style: TextStyle(
                  color: canDelete ? AppColors.danger : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
  typed.dispose();
  if (confirmed != true || !context.mounted) return;

  // Non-dismissible progress dialog while the server erases the account.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await ref.read(accountServiceProvider).deleteAccount();
    await ref.read(authProvider.notifier).logout();
    ref.invalidate(userProfileProvider);
    ref.invalidate(businessProfileProvider);
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss the progress dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not delete your account. Please try again or contact support.',
        ),
      ),
    );
  }
}
