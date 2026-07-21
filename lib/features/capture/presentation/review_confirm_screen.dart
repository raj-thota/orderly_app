import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/shared/widgets/confidence_bar.dart';

String _formatCurrency(double amount) {
  final n = amount.round();
  return '₹${n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d\d)+\d$)'), (m) => '${m[1]},')}';
}

const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

class ReviewConfirmScreen extends ConsumerStatefulWidget {
  const ReviewConfirmScreen({super.key});

  @override
  ConsumerState<ReviewConfirmScreen> createState() =>
      _ReviewConfirmScreenState();
}

class _ReviewConfirmScreenState extends ConsumerState<ReviewConfirmScreen> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Capture the confidence bucket up front: the controller is autoDispose, so
    // reading its draft after popUntil would see a reset state.
    final confidenceBucket = _confidenceBucket(
        ref.read(captureControllerProvider).draft.confidence);
    try {
      final result =
          await ref.read(captureControllerProvider.notifier).save();
      if (!mounted) return;
      // One shared refresh for every surface a save can touch (enquiries,
      // orders, work items) plus follow-up reminders. Do it while the widget —
      // and therefore `ref` — is still mounted, before we pop.
      refreshAfterCapture(ref);
      // fire-and-forget telemetry (non-blocking)
      ref.read(eventServiceProvider).track(
            'capture_confirmed',
            props: {'confidence_bucket': confidenceBucket},
          );
      navigator.popUntil((r) => r.isFirst);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved for ${result.customerName}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      debugPrint('capture save failed: $e');
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          const SnackBar(
              content: Text("Couldn't save. Please try again."),
              backgroundColor: AppColors.danger),
        );
      }
    }
  }

  String _confidenceBucket(double c) {
    if (c >= 0.8) return 'high';
    if (c >= 0.5) return 'medium';
    return 'low';
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(captureControllerProvider).draft;
    final existingEnquiries =
        ref.watch(enquiriesControllerProvider).valueOrNull ?? const [];
    final isDuplicate = hasOpenEnquiryFor(
      existing: existingEnquiries,
      phone: draft.phone,
      name: draft.name,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Review & Confirm'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (isDuplicate) ...[
            const _DuplicateBanner(),
            const SizedBox(height: AppSpacing.md),
          ],
          _Section(
            label: 'AI Confidence',
            child: ConfidenceBar(confidence: draft.confidence),
          ),
          const SizedBox(height: AppSpacing.md),
          _Section(
            label: 'Customer',
            child: _EditableRow(
              icon: Icons.person_outline_rounded,
              value: draft.name ?? 'Unknown',
              hint: 'Customer name',
              onChanged: (v) =>
                  ref.read(captureControllerProvider.notifier).setName(v),
            ),
          ),
          if (draft.phone != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _Section(
              label: 'Phone',
              child: _EditableRow(
                icon: Icons.phone_outlined,
                value: draft.phone!,
                hint: 'Phone number',
                onChanged: (v) =>
                    ref.read(captureControllerProvider.notifier).setPhone(v),
              ),
            ),
          ],
          if (draft.items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _Section(
              label: 'Items',
              child: Column(
                children: [
                  for (final item in draft.items)
                    _ItemRow(item: item),
                ],
              ),
            ),
          ],
          if (draft.budget != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Section(
              label: 'Budget',
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _formatCurrency(draft.budget!),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
          if (draft.followUpDate != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Section(
              label: 'Follow-up',
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(draft.followUpDate!),
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
          if (draft.notes != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Section(
              label: 'Notes',
              child: Text(
                draft.notes!,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Confirm & Save',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'You already have an open enquiry for this customer. '
                'Saving will add another — that\'s fine if it\'s a new request.',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

class _EditableRow extends StatefulWidget {
  const _EditableRow({
    required this.icon,
    required this.value,
    required this.hint,
    required this.onChanged,
  });
  final IconData icon;
  final String value;
  final String hint;
  final void Function(String) onChanged;

  @override
  State<_EditableRow> createState() => _EditableRowState();
}

class _EditableRowState extends State<_EditableRow> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(widget.icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: widget.onChanged,
              style: const TextStyle(
                  fontSize: 15, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintStyle:
                    const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final DraftItem item;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.circle, color: AppColors.primary, size: 6),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${item.qty}× ${item.name}',
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
            if (item.price != null)
              Text(
                _formatCurrency(item.price!),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary),
              ),
          ],
        ),
      );
}
