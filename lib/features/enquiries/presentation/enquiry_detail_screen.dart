import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/enquiries_provider.dart';
import '../data/capture_draft.dart';
import '../data/enquiry.dart';

class EnquiryDetailScreen extends ConsumerWidget {
  const EnquiryDetailScreen({super.key, required this.enquiry});

  final Enquiry enquiry;

  Future<void> _openUri(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the app')),
      );
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: enquiry.followUpDate ??
          DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(enquiriesControllerProvider.notifier)
          .reschedule(enquiry.id!, picked);
      messenger.showSnackBar(SnackBar(
          content: Text('Follow-up set for ${picked.day}/${picked.month}')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not update. Try again.')));
    }
  }

  Future<void> _convert(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Convert to order?'),
        content: Text(enquiry.productIsUnique
            ? 'This books ${enquiry.productName ?? 'the piece'} so it cannot be sold twice.'
            : 'Creates an order for ${enquiry.customerName ?? 'this customer'}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(enquiriesControllerProvider.notifier).convertToOrder(
        enquiry,
        [
          DraftItem(
              name: enquiry.productName ?? 'Item',
              qty: 1,
              price: enquiry.productPrice),
        ],
      );
      if (!context.mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Order created')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not convert. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = enquiry.customerPhone;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(enquiry.customerName ?? 'Enquiry')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if ((enquiry.message ?? '').isNotEmpty)
            AppCard(
              child: Text(enquiry.message!,
                  style: const TextStyle(height: 1.5)),
            ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(enquiry.followUpDate == null
                      ? 'No follow-up scheduled'
                      : 'Follow up ${enquiry.followUpDate!.day}/${enquiry.followUpDate!.month}'),
                  trailing: TextButton(
                    onPressed: () => _reschedule(context, ref),
                    child: const Text('Change'),
                  ),
                ),
                if (phone != null && phone.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openUri(
                              context, Uri.parse('https://wa.me/91$phone')),
                          icon: const Icon(Icons.chat_outlined, size: 18),
                          label: const Text('WhatsApp'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _openUri(context, Uri.parse('tel:$phone')),
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: const Text('Call'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Convert to order',
            onPressed: () => _convert(context, ref),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(enquiriesControllerProvider.notifier)
                    .markLost(enquiry.id!);
                if (context.mounted && Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              } catch (_) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Could not update. Try again.')));
              }
            },
            child: const Text('Mark as lost',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
