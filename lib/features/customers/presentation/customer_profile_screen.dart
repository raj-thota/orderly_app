import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/conversations/presentation/customer_workspace_screen.dart';
import 'package:orderly_app/features/customers/controller/customer_profile_provider.dart';
import 'package:orderly_app/features/customers/data/customer_stats.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/presentation/order_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomerProfileScreen extends ConsumerWidget {
  const CustomerProfileScreen({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  final String customerId;
  final String customerName;

  static final _mobileRe = RegExp(r'^[6-9]\d{9}$');

  String _waLink(String phone) => _mobileRe.hasMatch(phone)
      ? 'https://wa.me/91$phone'
      : 'https://wa.me/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(customerStatsProvider(customerId));
    final score = ref.watch(relationshipScoreProvider(customerId));
    final orders = ref.watch(ordersControllerProvider).valueOrNull ?? const [];
    final customerOrders =
        orders.where((o) => o.customerId == customerId).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(customerName),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load profile'),
              TextButton(
                onPressed: () =>
                    ref.invalidate(customerStatsProvider(customerId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (stats) => stats == null
            ? const Center(child: Text('Customer not found'))
            : _Body(
                stats: stats,
                score: score,
                recentOrders: customerOrders,
                onOpenChat: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerWorkspaceScreen(
                      customerId: customerId,
                      customerName: customerName,
                      phone: stats.phone,
                    ),
                  ),
                ),
                onWhatsApp: stats.phone != null
                    ? () => launchUrl(Uri.parse(_waLink(stats.phone!)),
                        mode: LaunchMode.externalApplication)
                    : null,
                onCall: stats.phone != null
                    ? () => launchUrl(
                        Uri.parse(
                            'tel:${stats.phone!.replaceAll(RegExp(r'\D'), '')}'),
                        mode: LaunchMode.externalApplication)
                    : null,
                onOrderTap: (o) => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(order: o)),
                ),
              ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.stats,
    required this.score,
    required this.recentOrders,
    required this.onOpenChat,
    this.onWhatsApp,
    this.onCall,
    required this.onOrderTap,
  });

  final CustomerStats stats;
  final double score;
  final List<Order> recentOrders;
  final VoidCallback onOpenChat;
  final Future<void> Function()? onWhatsApp;
  final Future<void> Function()? onCall;
  final void Function(Order) onOrderTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _hero(),
        const SizedBox(height: AppSpacing.lg),
        _statsCard(),
        const SizedBox(height: AppSpacing.lg),
        if (stats.aiFacts.isNotEmpty) ...[
          _aiFactsCard(),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (recentOrders.isNotEmpty) ...[
          _recentOrdersSection(context),
          const SizedBox(height: AppSpacing.lg),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onOpenChat,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Open Chat',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _hero() {
    return Column(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: AppColors.primary.withAlpha(20),
          child: Text(
            stats.name.characters.first.toUpperCase(),
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(stats.name,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        if (stats.phone != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(stats.phone!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (onWhatsApp != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: OutlinedButton.icon(
                  onPressed: onWhatsApp,
                  icon: const Icon(Icons.chat_outlined, size: 16),
                  label: const Text('WhatsApp'),
                ),
              ),
            if (onCall != null)
              OutlinedButton.icon(
                onPressed: onCall,
                icon: const Icon(Icons.call_outlined, size: 16),
                label: const Text('Call'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _statsCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Relationship Score header
          Row(
            children: [
              const Text('Relationship Score',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const Spacer(),
              _ScoreStars(score: score),
              const SizedBox(width: AppSpacing.sm),
              Text(score.toStringAsFixed(1),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 15)),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          _statRow('Total Orders', '${stats.totalOrders}'),
          const SizedBox(height: AppSpacing.sm),
          _statRow('Lifetime Value', Money.inr(stats.lifetimeValue),
              valueColor: AppColors.money),
          const SizedBox(height: AppSpacing.sm),
          _statRow('Outstanding', Money.inr(stats.outstanding),
              valueColor:
                  stats.outstanding > 0 ? AppColors.dues : AppColors.textPrimary),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: valueColor ?? AppColors.textPrimary)),
      ],
    );
  }

  Widget _aiFactsCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 16, color: AppColors.aiAccent),
              const SizedBox(width: AppSpacing.sm),
              const Text('AI Insights',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final fact in stats.aiFacts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(color: AppColors.aiAccent)),
                  Expanded(
                    child: Text(fact.fact,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _recentOrdersSection(BuildContext context) {
    final recent = recentOrders.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent Orders',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        for (final order in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _Card(
              onTap: () => onOrderTap(order),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderNumber != null
                              ? '#${order.orderNumber}'
                              : 'Order',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                        Text(Money.inr(order.grandTotal),
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _orderStatusColor(order.status).withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      order.status,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _orderStatusColor(order.status)),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static Color _orderStatusColor(String status) {
    switch (status) {
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ScoreStars extends StatelessWidget {
  const _ScoreStars({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (score >= i + 1) {
          return const Icon(Icons.star_rounded,
              size: 16, color: AppColors.accent);
        } else if (score >= i + 0.5) {
          return const Icon(Icons.star_half_rounded,
              size: 16, color: AppColors.accent);
        } else {
          return const Icon(Icons.star_outline_rounded,
              size: 16, color: AppColors.border);
        }
      }),
    );
  }
}
