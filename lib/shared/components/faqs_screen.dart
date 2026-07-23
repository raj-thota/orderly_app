import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_screen_header.dart';

/// Frequently asked questions, reachable from the Help & Support screen.
class FaqsScreen extends StatelessWidget {
  const FaqsScreen({super.key});

  static const List<(String, String)> _faqs = [
    (
      'How do I add a new lead or enquiry?',
      'Tap the + button and paste a WhatsApp message, or use voice input. '
          'Closr reads it and creates the enquiry for you.',
    ),
    (
      'What is Focus Mode?',
      'Tap "Start My Work" to handle your pending items one at a time, '
          'distraction-free. Closr picks the next best thing to do.',
    ),
    (
      'How do I record a payment?',
      'Open the order and tap "Record Payment". You can also collect over UPI '
          'and Closr tracks the outstanding dues automatically.',
    ),
    (
      'How do I create and share an invoice?',
      'Open an order and generate the invoice. Pick a template and share the '
          'branded PDF with your customer.',
    ),
    (
      'How do I change my invoice number or tax settings?',
      'Go to Settings → Invoice Settings to set your prefix, starting number, '
          'GST, currency, footer and logo.',
    ),
    (
      'Is my business data secure?',
      'Yes. Your data is stored securely and scoped to your account only. '
          'We never sell your data.',
    ),
    (
      'How do I upgrade to Pro?',
      'Go to Business → Go Pro. Pro (₹499/month) unlocks AI capture, the '
          'daily chase list, AI-drafted replies and the Closr AI assistant. '
          'Core features stay free.',
    ),
    (
      'How do I contact support?',
      'Go to Settings → Contact Support to email us at closrsupport@gmail.com. '
          'We usually reply within 24 hours.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appScreenHeader('FAQs'),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _faqs.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final (question, answer) = _faqs[i];
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                iconColor: AppColors.primary,
                collapsedIconColor: AppColors.textSecondary,
                title: Text(
                  question,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    answer,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
