import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'faqs_screen.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Help & Support")),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          /// INTRO
          _card(
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Closr",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  "Manage leads, follow-ups, and orders from your chats — all in one place.",
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// QUICK HELP
          _section("Quick Help"),

          _card(
            child: const Column(
              children: [
                _HelpItem(
                  icon: Icons.bolt_rounded,
                  title: 'Capture a lead',
                  subtitle:
                      'Paste a WhatsApp message or use voice — Closr logs the enquiry.',
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.today_rounded,
                  title: 'Work your day',
                  subtitle:
                      'Today shows all your orders and enquiries in one pipeline.',
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.center_focus_strong_rounded,
                  title: 'Work in Focus Mode',
                  subtitle:
                      'Start My Work to handle items one at a time, distraction-free.',
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.payments_rounded,
                  title: 'Record payments',
                  subtitle:
                      'Track order status, log payments, and see outstanding dues.',
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.receipt_long_rounded,
                  title: 'Share invoices',
                  subtitle:
                      'Generate branded invoice PDFs and send them to customers.',
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.notifications_active_rounded,
                  title: 'Never miss a follow-up',
                  subtitle: 'Smart reminders keep warm leads from going cold.',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// FAQs
          _section("FAQs"),

          _card(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.quiz_rounded,
                color: AppColors.primary,
              ),
              title: const Text("Frequently Asked Questions"),
              subtitle: const Text("Answers to common questions"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FaqsScreen()),
              ),
            ),
          ),

          const SizedBox(height: 30),

          /// VERSION
          const Center(
            child: Text(
              "Closr • Version 1.0.0",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: child,
    );
  }
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _HelpItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
