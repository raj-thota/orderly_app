import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';

/// Fake-door paywall. Nothing is charged: tapping the CTA only records intent
/// so we can measure willingness-to-pay before building real billing. The
/// price shown here is the value under test, not a live plan.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  /// Monthly price under test, in INR. Sent with the tap event so the funnel
  /// records which number sellers reacted to.
  static const int priceInr = 299;

  static const List<String> features = [
    'AI enquiry capture from DMs & screenshots',
    'Re-market broadcasts to past buyers',
    'Branded invoices with your logo',
    'Smart daily chase list',
  ];

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(eventServiceProvider)
        .track('paywall_view', props: {'price': SubscriptionScreen.priceInr});
  }

  void _joinEarlyAccess() {
    ref
        .read(eventServiceProvider)
        .track('paywall_tap', props: {'price': SubscriptionScreen.priceInr});
    setState(() => _joined = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Go Pro'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _joined ? _confirmed() : _offer(),
      ),
    );
  }

  Widget _offer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _priceHeader(),
          const SizedBox(height: AppSpacing.xl),
          ...SubscriptionScreen.features.map(_featureRow),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Get early access',
            onPressed: _joinEarlyAccess,
          ),
          const SizedBox(height: AppSpacing.md),
          const Center(
            child: Text(
              "You won't be charged. We'll reach out before launch.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Closr Pro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹${SubscriptionScreen.priceInr}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                ' / month',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featureRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmed() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 64),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            "You're on the list 🎉",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            "We'll ping you on WhatsApp when Closr Pro is ready.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
