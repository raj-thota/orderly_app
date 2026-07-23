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

  static const int proPriceInr = 499;
  static const int whatsappPriceInr = 999;

  static const List<String> _proFeatures = [
    'AI capture from DMs, screenshots & voice',
    'Auto-prioritised daily chase list',
    'AI-drafted follow-ups & payment reminders',
    'Customer 360 with AI summaries',
    'Closr AI business assistant',
  ];

  static const List<String> _freeFeatures = [
    'Unlimited orders & invoices',
    'Manual capture & product catalog',
    'Customer directory & payment tracking',
    'Follow-up reminders & notifications',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(subscriptionProvider);

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
          data: (sub) => _Body(sub: sub),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.sub});
  final Subscription? sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkoutState = ref.watch(checkoutControllerProvider);
    final entitlement = sub?.entitlement ?? EntitlementStatus.gated;
    final trialDays = sub?.trialDaysLeft ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entitlement == EntitlementStatus.trialing)
            _StatusLine(
              'Your free trial gives you everything Pro has — '
              '$trialDays day${trialDays == 1 ? '' : 's'} left.',
            )
          else if (entitlement == EntitlementStatus.gated)
            const _StatusLine(
              'Your trial has ended. Core features stay free forever — '
              'Pro brings the AI back.',
            ),
          _ProCard(
            sub: sub,
            entitlement: entitlement,
            loading: checkoutState.loading,
            error: checkoutState.error,
            onSubscribe: () => _startCheckout(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _FreeCard(),
          const SizedBox(height: AppSpacing.lg),
          const _WhatsAppCard(),
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
    ref.read(eventServiceProvider).track(
      'checkout_started',
      props: {'gateway': 'razorpay', 'plan': 'pro_monthly'},
    );
    final uri = await ref
        .read(checkoutControllerProvider.notifier)
        .startCheckout(gateway: 'razorpay', plan: 'pro_monthly');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}

class _ProCard extends StatelessWidget {
  const _ProCard({
    required this.sub,
    required this.entitlement,
    required this.loading,
    this.error,
    required this.onSubscribe,
  });

  final Subscription? sub;
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
              const Text(
                'Closr Pro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (entitlement == EntitlementStatus.trialing)
                _Badge(
                  'Trial · ${sub?.trialDaysLeft ?? 0}d left',
                  Colors.white.withAlpha(50),
                  Colors.white,
                )
              else if (entitlement == EntitlementStatus.active)
                _Badge('Active', Colors.green.shade700, Colors.white),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹${SubscriptionScreen.proPriceInr}',
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
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Everything free, plus your AI sales assistant:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final f in SubscriptionScreen._proFeatures)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      f,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          if (entitlement == EntitlementStatus.active)
            _ActiveFooter(sub: sub)
          else
            FilledButton(
              key: const Key('cta_start_trial'),
              onPressed: loading ? null : onSubscribe,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      entitlement == EntitlementStatus.trialing
                          ? 'Subscribe now · ₹${SubscriptionScreen.proPriceInr}/mo'
                          : 'Get Closr Pro · ₹${SubscriptionScreen.proPriceInr}/mo',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Active subscribers must never be routed back into checkout — a second
/// gateway subscription would double-bill them. Cancellation goes through
/// support until a self-serve portal exists.
class _ActiveFooter extends StatelessWidget {
  const _ActiveFooter({required this.sub});
  final Subscription? sub;

  @override
  Widget build(BuildContext context) {
    final renews = sub?.currentPeriodEnd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (renews != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Renews on ${renews.day}/${renews.month}/${renews.year}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        OutlinedButton(
          key: const Key('cta_manage'),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final ok = await launchUrl(
              Uri(
                scheme: 'mailto',
                path: 'closrsupport@gmail.com',
                query:
                    'subject=${Uri.encodeComponent('Manage my Closr Pro subscription')}',
              ),
            );
            if (!ok) {
              messenger.showSnackBar(const SnackBar(
                  content: Text('No email app found — write to '
                      'closrsupport@gmail.com')));
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white54),
          ),
          child: const Text('Manage · Contact support'),
        ),
      ],
    );
  }
}

class _FreeCard extends StatelessWidget {
  const _FreeCard();

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
          const Text(
            'Free forever',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Run your business by hand at no cost — with or without Pro.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final f in SubscriptionScreen._freeFeatures)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      f,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WhatsAppCard extends StatelessWidget {
  const _WhatsAppCard();

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
              const Text(
                'Pro + WhatsApp',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text(
                  'Coming soon',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '₹${SubscriptionScreen.whatsappPriceInr} / month',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Everything in Pro, plus:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final f in const [
            'WhatsApp Business connected to Closr',
            'AI replies sent straight from the app',
            'Team members & shared inbox',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_rounded,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    f,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
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
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}
