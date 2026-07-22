import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  static const int priceInr = 999;

  static const List<String> _proFeatures = [
    'AI capture from DMs, screenshots & voice',
    'Auto-prioritised daily chase list',
    'AI-drafted WhatsApp follow-ups & reminders',
    'Branded invoices with your logo',
    'Customer 360 relationship score',
    'Closr AI business assistant',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(subscriptionProvider);
    final entitlement = ref.watch(entitlementProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Closr Pro'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: subAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text(
                "Couldn't load your subscription. Please try again.",
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (_) => _Body(entitlement: entitlement),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.entitlement});
  final EntitlementStatus entitlement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkoutState = ref.watch(checkoutControllerProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProCard(
            entitlement: entitlement,
            loading: checkoutState.loading,
            error: checkoutState.error,
            onSubscribe: () => _startCheckout(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),
          _BusinessCard(),
          const SizedBox(height: AppSpacing.xl),
          const Center(
            child: Text(
              'Secure checkout via Razorpay · Cancel anytime',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCheckout(BuildContext context, WidgetRef ref) async {
    ref.read(eventServiceProvider).track('checkout_started', props: {'gateway': 'razorpay'});
    final uri = await ref
        .read(checkoutControllerProvider.notifier)
        .startCheckout(gateway: 'razorpay');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _ProCard extends StatelessWidget {
  const _ProCard({
    required this.entitlement,
    required this.loading,
    this.error,
    required this.onSubscribe,
  });

  final EntitlementStatus entitlement;
  final bool loading;
  final String? error;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(
            children: [
              const Text('Closr Pro',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              if (entitlement == EntitlementStatus.trialing)
                _Badge('Trial active', Colors.white.withAlpha(50), Colors.white)
              else if (entitlement == EntitlementStatus.active)
                _Badge('Active', Colors.green.shade700, Colors.white),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: const [
              Text('₹999',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold)),
              Text(' / month',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final f in SubscriptionScreen._proFeatures)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text(f,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14))),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(error!,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          _CtaButton(
            entitlement: entitlement,
            loading: loading,
            onTap: onSubscribe,
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.entitlement,
    required this.loading,
    required this.onTap,
  });

  final EntitlementStatus entitlement;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (entitlement == EntitlementStatus.active) {
      return OutlinedButton(
        key: const Key('cta_manage'),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white54),
        ),
        child: const Text('Manage subscription'),
      );
    }

    return FilledButton(
      key: const Key('cta_start_trial'),
      onPressed: loading ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        minimumSize: const Size(double.infinity, 48),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Text(
              entitlement == EntitlementStatus.trialing
                  ? 'Subscribe now  ₹999/mo'
                  : 'Start Free Trial',
              style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Business',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text('Coming soon',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('₹2,499 / month',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.md),
          const Text('Everything in Pro, plus:',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: AppSpacing.sm),
          for (final f in const [
            'Team members & shared inbox',
            'WhatsApp Business API integration',
            'API access',
            'Priority support',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(Icons.check_rounded,
                      color: AppColors.textSecondary, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Text(f,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.bgColor, this.textColor);
  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: textColor)),
    );
  }
}
