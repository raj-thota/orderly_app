import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/auth/controller/auth_controller.dart';
import 'package:orderly_app/features/invoices/presentation/invoices_screen.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void push(Widget screen) => Navigator.push(
        context, MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        children: [
          _SectionHeader('Account'),
          _SettingsTile(
            icon: Icons.badge_rounded,
            title: 'Business Profile',
            subtitle: 'Name, phone, address, UPI, GST',
            onTap: () => push(const ProfileScreen()),
          ),
          _SectionHeader('Billing'),
          _SettingsTile(
            icon: Icons.receipt_long_rounded,
            title: 'Invoice Settings',
            subtitle: 'Templates, numbering, logo',
            onTap: () => push(const InvoicesScreen()),
          ),
          _SectionHeader('Legal'),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Data & Privacy',
            onTap: () => _showStatic(
              context,
              'Data & Privacy',
              'Closr stores your business data securely in Supabase (EU-west). '
                  'We never sell your data. Your messages and customer information '
                  'are end-to-end encrypted in transit and encrypted at rest.\n\n'
                  'To request data export or deletion, contact privacy@closr.app.',
            ),
          ),
          _SettingsTile(
            icon: Icons.help_outline_rounded,
            title: 'Help & Support',
            onTap: () => _showStatic(
              context,
              'Help & Support',
              'For help, email support@closr.app or visit closr.app/help.\n\n'
                  'We typically respond within 24 hours.',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout_rounded,
                  color: AppColors.danger, size: 18),
              label: const Text('Sign Out',
                  style: TextStyle(color: AppColors.danger)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.danger),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  void _showStatic(BuildContext context, String title, String body) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, ctl) => Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ListView(
            controller: ctl,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: AppSpacing.lg),
              Text(body,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColors.textSecondary),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 22),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 15)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12))
            : null,
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
