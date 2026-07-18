import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      content: const Text('You will need to sign in again to access your shop.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Log out',
              style: TextStyle(color: AppColors.danger)),
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
