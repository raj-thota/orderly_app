import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/assistant/presentation/assistant_screen.dart';
import 'package:orderly_app/features/catalog/presentation/catalog_screen.dart';
import 'package:orderly_app/features/catalog/presentation/product_form_screen.dart';
import 'package:orderly_app/features/invoices/presentation/invoices_screen.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';
import 'package:orderly_app/features/settings/presentation/settings_screen.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';
import 'package:orderly_app/features/subscription/presentation/subscription_screen.dart';

/// Business tab: hub for everything that isn't the daily pipeline.
/// Customers entry arrives in M6; Analytics later.
class BusinessHubScreen extends ConsumerWidget {
  const BusinessHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void push(Widget screen) => Navigator.push(
        context, MaterialPageRoute(builder: (_) => screen));

    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final (planTitle, planSubtitle) = switch (sub?.entitlement) {
      EntitlementStatus.active => ('Closr Pro', 'Active · manage your plan'),
      EntitlementStatus.trialing => (
          'Go Pro',
          'Trial · ${sub!.trialDaysLeft} day${sub.trialDaysLeft == 1 ? '' : 's'} left',
        ),
      _ => ('Go Pro', 'Unlock AI · ₹499/month'),
    };

    final tiles = [
      (Icons.auto_awesome_rounded, 'Closr AI', 'Your AI business assistant',
          () => push(const AssistantScreen())),
      (Icons.storefront_rounded, 'Catalog', 'Your products and pieces',
          () => push(const _CatalogPage())),
      (Icons.receipt_long_rounded, 'Invoices', 'Generated invoices',
          () => push(const InvoicesScreen())),
      (Icons.badge_rounded, 'Business Profile', 'Name, contact, payment, GST',
          () => push(const ProfileScreen())),
      (Icons.workspace_premium_rounded, planTitle, planSubtitle,
          () => push(const SubscriptionScreen())),
      (Icons.settings_rounded, 'Settings', 'Notifications, invoices, support',
          () => push(const SettingsScreen())),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text('Business',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.lg),
            for (final (icon, title, subtitle, onTap) in tiles)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        side: const BorderSide(color: AppColors.border)),
                    leading: Icon(icon, color: AppColors.primary),
                    title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary),
                    onTap: onTap,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// CatalogScreen is a bare tab child (no Scaffold); this wrapper provides one
/// when it's pushed as a route.
class _CatalogPage extends StatelessWidget {
  const _CatalogPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Catalog'),
        actions: [
          IconButton(
            tooltip: 'Add piece',
            icon: const Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductFormScreen()),
            ),
          ),
        ],
      ),
      body: const CatalogScreen(),
    );
  }
}
