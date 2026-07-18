import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_settings_screen.dart';
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';
import 'package:orderly_app/shared/components/help_and_support_screen.dart';
import 'package:orderly_app/shared/components/privacy_policy_screen.dart';
import 'package:orderly_app/shared/components/terms_screen.dart';
import 'package:orderly_app/shared/utils/session_actions.dart';
import 'package:orderly_app/shared/widgets/app_screen_header.dart';
import 'package:orderly_app/shared/widgets/settings_section.dart';
import 'package:orderly_app/shared/widgets/settings_tile.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void push(Widget s) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => s));

    Future<void> mail(String subject) async {
      final uri = Uri.parse(
          'mailto:closrsupport@gmail.com?subject=${Uri.encodeComponent(subject)}');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appScreenHeader('Settings'),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          SettingsSection(title: 'General', children: [
            SettingsTile(
                icon: Icons.notifications_rounded,
                title: 'Notifications',
                onTap: () => push(const NotificationsScreen())),
            const SettingsTile(
                icon: Icons.language_rounded,
                title: 'Language',
                subtitle: 'English',
                comingSoon: true),
            const SettingsTile(
                icon: Icons.dark_mode_rounded, title: 'Theme', comingSoon: true),
          ]),
          SettingsSection(title: 'Business', children: [
            SettingsTile(
                icon: Icons.receipt_long_rounded,
                title: 'Invoice Settings',
                subtitle: 'Prefix, tax, currency, footer, logo',
                onTap: () => push(const InvoiceSettingsScreen())),
            SettingsTile(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Payment Settings',
                subtitle: 'UPI, bank, default method',
                onTap: () =>
                    push(const ProfileScreen(scrollTo: ProfileAnchor.payment))),
            SettingsTile(
                icon: Icons.percent_rounded,
                title: 'Tax & GST',
                onTap: () => push(const InvoiceSettingsScreen())),
          ]),
          SettingsSection(title: 'Security', children: [
            SettingsTile(
                icon: Icons.privacy_tip_rounded,
                title: 'Data Privacy',
                onTap: () => push(const PrivacyPolicyScreen())),
            const SettingsTile(
                icon: Icons.verified_user_rounded,
                title: 'Permissions',
                comingSoon: true),
            const SettingsTile(
                icon: Icons.lock_rounded, title: 'Security', comingSoon: true),
          ]),
          SettingsSection(title: 'Support', children: [
            SettingsTile(
                icon: Icons.help_center_rounded,
                title: 'Help Center',
                onTap: () => push(const HelpSupportScreen())),
            SettingsTile(
                icon: Icons.support_agent_rounded,
                title: 'Contact Support',
                onTap: () => mail('Closr Support')),
            SettingsTile(
                icon: Icons.bug_report_rounded,
                title: 'Report a Bug',
                onTap: () => mail('Closr Bug Report')),
            SettingsTile(
                icon: Icons.lightbulb_rounded,
                title: 'Request a Feature',
                onTap: () => mail('Closr Feature Request')),
            const SettingsTile(
                icon: Icons.quiz_rounded, title: 'FAQs', comingSoon: true),
          ]),
          SettingsSection(title: 'About', children: [
            const SettingsTile(
                icon: Icons.info_rounded,
                title: 'App Version',
                subtitle: 'Closr 1.0.0'),
            SettingsTile(
                icon: Icons.description_rounded,
                title: 'Terms & Conditions',
                onTap: () => push(const TermsScreen())),
            SettingsTile(
                icon: Icons.policy_rounded,
                title: 'Privacy Policy',
                onTap: () => push(const PrivacyPolicyScreen())),
            SettingsTile(
                icon: Icons.code_rounded,
                title: 'Open Source Licenses',
                onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Closr',
                      applicationVersion: '1.0.0',
                    )),
          ]),
          SettingsSection(title: 'Account', children: [
            SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Logout',
                danger: true,
                onTap: () => confirmAndLogout(context, ref)),
          ]),
          const SizedBox(height: AppSpacing.xl),
        ],
        ),
      ),
    );
  }
}
