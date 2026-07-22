import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/features/quotations/data/quotation.dart';
import 'package:orderly_app/features/quotations/presentation/quote_share_sheet.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/enquiries_provider.dart';
import '../data/capture_draft.dart';
import '../data/enquiry.dart';

class EnquiryDetailScreen extends ConsumerStatefulWidget {
  const EnquiryDetailScreen({super.key, required this.enquiry});

  final Enquiry enquiry;

  @override
  ConsumerState<EnquiryDetailScreen> createState() =>
      _EnquiryDetailScreenState();
}

class _EnquiryDetailScreenState extends ConsumerState<EnquiryDetailScreen> {
  bool _busy = false;

  Future<void> _openUri(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the app')),
      );
    }
  }

  Future<void> _reschedule(BuildContext context, Enquiry live) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: live.followUpDate ??
          DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(enquiriesControllerProvider.notifier)
          .reschedule(live.id!, picked);
      messenger.showSnackBar(SnackBar(
          content: Text('Follow-up set for ${picked.day}/${picked.month}')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not update. Try again.')));
    }
  }

  bool _quoting = false;

  Future<void> _sendQuote(Enquiry live) async {
    if (_quoting) return; // await below opens a double-tap window
    _quoting = true;
    try {
      await _sendQuoteInner(live);
    } finally {
      _quoting = false;
    }
  }

  Future<void> _sendQuoteInner(Enquiry live) async {
    // Await the profile rather than watching it in build: this screen only
    // needs it here, and the future is normally already resolved by tap time.
    BusinessProfile? profile;
    try {
      profile = await ref.read(businessProfileProvider.future);
    } catch (_) {}
    if (!mounted) return;
    final products = ref.read(productsControllerProvider).valueOrNull ?? const [];

    // Enquiries carry at most one attached product; catalog matching fills in
    // the canonical name/price. Anything else stays editable in the sheet.
    final lines = matchCatalog(
      [
        DraftItem(
          name: live.productName ?? 'Item',
          qty: 1,
          price: live.productPrice,
        ),
      ],
      products,
    );
    final quote = Quotation.compose(
      businessName: profile?.name ?? 'My Shop',
      upiId: profile?.upiId,
      upiName: profile?.upiName,
      customerName: live.customerName,
      lines: lines,
    );

    final messenger = ScaffoldMessenger.of(context);
    final sentText = await showQuoteShareSheet(
      context,
      QuoteShareRequest(
        message: quote.message,
        customerPhone: live.customerPhone,
        customerEmail: live.customerEmail,
        businessName: profile?.name,
      ),
    );
    if (sentText == null || !mounted) return;

    final id = live.id;
    if (id == null) return; // nothing to record against

    try {
      await ref
          .read(enquiriesControllerProvider.notifier)
          .recordQuoteSent(id, sentText);
      messenger.showSnackBar(const SnackBar(content: Text('Quote sent')));
    } catch (_) {
      // The quote already went out; losing the activity note is non-fatal.
      messenger.showSnackBar(const SnackBar(
          content: Text('Quote sent, but could not update the timeline')));
    }
  }

  Future<void> _convert(BuildContext context, Enquiry live) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Convert to order?'),
        content: Text(live.productIsUnique
            ? 'This books ${live.productName ?? 'the piece'} so it cannot be sold twice.'
            : 'Creates an order for ${live.customerName ?? 'this customer'}.'),
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

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(enquiriesControllerProvider.notifier).convertToOrder(
        live,
        [
          DraftItem(
              name: live.productName ?? 'Item',
              qty: 1,
              price: live.productPrice),
        ],
      );
      if (!context.mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Order created')));
    } catch (e) {
      final isUnavailable = e.toString().contains('piece_unavailable');
      messenger.showSnackBar(SnackBar(
          content: Text(isUnavailable
              ? 'This piece is already booked or sold.'
              : 'Could not convert. Try again.')));
      if (isUnavailable) {
        ref.read(enquiriesControllerProvider.notifier).load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref
            .watch(enquiriesControllerProvider)
            .valueOrNull
            ?.where((e) => e.id == widget.enquiry.id)
            .firstOrNull ??
        widget.enquiry;

    final phone = live.customerPhone;
    String? digits;
    String? waTarget;
    if (phone != null && phone.isNotEmpty) {
      digits = phone.replaceAll(RegExp(r'\D'), '');
      waTarget = digits.length == 10 ? '91$digits' : digits;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(live.customerName ?? 'Enquiry')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if ((live.message ?? '').isNotEmpty)
            AppCard(
              child: Text(live.message!,
                  style: const TextStyle(height: 1.5)),
            ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(live.followUpDate == null
                      ? 'No follow-up scheduled'
                      : 'Follow up ${live.followUpDate!.day}/${live.followUpDate!.month}'),
                  trailing: TextButton(
                    onPressed: () => _reschedule(context, live),
                    child: const Text('Change'),
                  ),
                ),
                if (phone != null && phone.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openUri(
                              context,
                              Uri.parse('https://wa.me/$waTarget')),
                          icon: const Icon(Icons.chat_outlined, size: 18),
                          label: const Text('WhatsApp'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _openUri(context, Uri.parse('tel:+$waTarget')),
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
          OutlinedButton.icon(
            onPressed: () => _sendQuote(live),
            icon: const Icon(Icons.request_quote_outlined, size: 18),
            label: const Text('Send quote'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppPrimaryButton(
            label: 'Convert to order',
            loading: _busy,
            onPressed: () => _convert(context, live),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () async {
              if (_busy) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(enquiriesControllerProvider.notifier)
                    .markLost(live.id!);
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
