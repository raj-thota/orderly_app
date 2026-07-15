import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

// ─── Nudge data ──────────────────────────────────────────────────────────────

class _NudgeData {
  const _NudgeData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

// ─── Stat tile ───────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.badgeText,
    required this.badgeColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String badgeText;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Attention tile ───────────────────────────────────────────────────────────

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.item,
    required this.onTap,
  });

  final AiWorkItem item;
  final VoidCallback onTap;

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'high':
        return AppColors.danger;
      case 'medium':
        return AppColors.warning;
      case 'low':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  String _priorityLabel(String priority) {
    if (priority.isEmpty) return priority;
    return priority[0].toUpperCase() + priority.substring(1);
  }

  String _actionLabel(String kind) {
    switch (kind) {
      case 'payment_reminder':
      case 'overdue_payment':
        return 'Send Reminder';
      case 'follow_up':
      case 'call':
        return 'Follow Up';
      default:
        return 'Message';
    }
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays >= 1) return '${diff.inDays} days ago';
    if (diff.inHours >= 1) return '${diff.inHours} hours ago';
    return 'Today';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.aiSurface,
              child: Text(
                _initials(item.customerName),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.customerName ?? item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _priorityColor(item.priority),
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          _priorityLabel(item.priority),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.context ?? item.title,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _timeAgo(item.createdAt),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (item.amount != null)
                  Text(
                    Money.inr(item.amount!),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: Text(_actionLabel(item.kind)),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── AI action card ───────────────────────────────────────────────────────────

class _AiActionCard extends StatelessWidget {
  const _AiActionCard({
    required this.item,
    required this.onTap,
  });

  final AiWorkItem item;
  final VoidCallback onTap;

  _CardConfig _config(AiWorkItem item) {
    final fullName = item.customerName ?? 'customer';
    // Use first name only in card descriptions to keep text concise and unique.
    final firstName = fullName.split(' ').first;
    switch (item.kind) {
      case 'payment_reminder':
      case 'overdue_payment':
        return _CardConfig(
          icon: Icons.chat_rounded,
          color: const Color(0xFF25D366),
          desc: 'Send price to $firstName',
          cta: 'Send Now',
        );
      case 'follow_up':
      case 'call':
        return _CardConfig(
          icon: Icons.phone_outlined,
          color: AppColors.primary,
          desc: 'Call follow-up for $fullName',
          cta: 'Call Now',
        );
      case 'share_catalog':
      case 'offer':
        return _CardConfig(
          icon: Icons.card_giftcard_outlined,
          color: AppColors.warning,
          desc: 'Offer discount to $firstName',
          cta: 'Create Offer',
        );
      default:
        return _CardConfig(
          icon: Icons.message_outlined,
          color: AppColors.aiAccent,
          desc: 'Message $firstName',
          cta: 'Message',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config(item);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 148,
        margin: const EdgeInsets.only(right: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cfg.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(cfg.icon, color: cfg.color, size: 20),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              cfg.desc,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              cfg.cta,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardConfig {
  const _CardConfig({
    required this.icon,
    required this.color,
    required this.desc,
    required this.cta,
  });
  final IconData icon;
  final Color color;
  final String desc;
  final String cta;
}

// ─── Today screen ─────────────────────────────────────────────────────────────

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, required this.onNavigate});

  final void Function(int tab) onNavigate;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final PageController _nudgePageCtrl = PageController();
  int _nudgePage = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(eventServiceProvider).track('brief_view');
      ref.read(workItemsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _nudgePageCtrl.dispose();
    super.dispose();
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersControllerProvider).valueOrNull ?? const [];
    final enquiries =
        ref.watch(enquiriesControllerProvider).valueOrNull ?? const [];
    final name =
        ref.watch(userProfileProvider).value?['business_name'] ?? '';
    final now = DateTime.now();
    final brief =
        buildTodayBrief(orders: orders, enquiries: enquiries, now: now);
    final workState = ref.watch(workItemsProvider);

    // Build nudges
    final nudges = <_NudgeData>[];
    if (brief.dueFollowUps > 0) {
      nudges.add(_NudgeData(
        icon: Icons.schedule_rounded,
        title:
            '${brief.dueFollowUps} follow-up(s) need your attention',
        subtitle: 'Review and take action',
        onTap: () => widget.onNavigate(1),
      ));
    }
    if (brief.outstanding > 0) {
      nudges.add(_NudgeData(
        icon: Icons.currency_rupee_rounded,
        title:
            '${Money.inr(brief.outstanding)} outstanding payments',
        subtitle: 'Collect payments now',
        onTap: () => widget.onNavigate(2),
      ));
    }
    if (brief.ordersToday > 0) {
      nudges.add(_NudgeData(
        icon: Icons.shopping_bag_outlined,
        title: '${brief.ordersToday} new order(s) placed today',
        subtitle: 'View your orders',
        onTap: () => widget.onNavigate(2),
      ));
    }

    // Nudge page desync guard
    if (nudges.isNotEmpty && _nudgePage >= nudges.length) {
      _nudgePage = nudges.length - 1;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(workState.pendingCount),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(ordersControllerProvider.notifier).load();
            await ref.read(enquiriesControllerProvider.notifier).load();
            await ref.read(workItemsProvider.notifier).load();
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Greeting
              _buildGreeting(name, now),
              const SizedBox(height: AppSpacing.lg),

              // Glance card
              _buildGlanceCard(brief),
              const SizedBox(height: AppSpacing.lg),

              // Nudge carousel
              if (nudges.isNotEmpty) ...[
                _buildNudgeCarousel(nudges),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Needs your attention
              if (workState.items.isNotEmpty) ...[
                _buildAttentionSection(workState),
                const SizedBox(height: AppSpacing.lg),

                // AI suggested actions
                _buildAiActionsSection(workState),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(int pendingCount) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
        onPressed: () {},
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
          SizedBox(width: 4),
          Text(
            'Closr',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined,
                  color: AppColors.textPrimary),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()),
                );
              },
            ),
            if (pendingCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$pendingCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGreeting(String name, DateTime now) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting(now)}, $name 👋',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          "Here's what's happening with your business today.",
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildGlanceCard(TodayBrief brief) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.briefGradientStart, AppColors.briefGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today at a glance',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.md),
          Stack(
            children: [
              Row(
                children: [
                  _StatTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Follow-ups\ndue',
                    value: '${brief.dueFollowUps}',
                    badgeText: brief.dueFollowUps > 0
                        ? 'Needs attention'
                        : 'All caught up',
                    badgeColor: brief.dueFollowUps > 0
                        ? AppColors.danger
                        : AppColors.success,
                  ),
                  _StatTile(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Orders\ntoday',
                    value: '${brief.ordersToday}',
                    badgeText:
                        brief.ordersToday > 0 ? 'New order' : 'No orders',
                    badgeColor: brief.ordersToday > 0
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                  _StatTile(
                    icon: Icons.currency_rupee_rounded,
                    label: 'Revenue\ntoday',
                    value: brief.revenueToday > 0
                        ? Money.inr(brief.revenueToday)
                        : '₹0',
                    badgeText: brief.revenueToday > 0
                        ? 'Sales today'
                        : 'No sales yet',
                    badgeColor: brief.revenueToday > 0
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  _StatTile(
                    icon: Icons.layers_outlined,
                    label: 'Outstanding',
                    value: Money.inr(brief.outstanding),
                    badgeText: 'Total due',
                    badgeColor: AppColors.info,
                  ),
                  const SizedBox(width: 80),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Image.asset(
                  'assets/robo.png',
                  width: 72,
                  height: 72,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 72),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              onPressed: () => widget.onNavigate(1),
              child: const Text(
                'Start My Work →',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNudgeCarousel(List<_NudgeData> nudges) {
    return Column(
      children: [
        SizedBox(
          height: 88,
          child: PageView.builder(
            controller: _nudgePageCtrl,
            itemCount: nudges.length,
            onPageChanged: (i) => setState(() => _nudgePage = i),
            itemBuilder: (_, i) {
              final nudge = nudges[i];
              return GestureDetector(
                onTap: nudge.onTap,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(nudge.icon, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                nudge.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                nudge.subtitle,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (nudges.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(nudges.length, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _nudgePage == i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _nudgePage == i
                      ? AppColors.primary
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildAttentionSection(WorkItemsState workState) {
    final displayItems = workState.items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Needs your attention',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => widget.onNavigate(1),
              child: Text(
                'View all (${workState.pendingCount})',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final item in displayItems) ...[
          _AttentionTile(
            item: item,
            onTap: () => widget.onNavigate(1),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _buildAiActionsSection(WorkItemsState workState) {
    final displayItems = workState.items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.auto_awesome,
                    size: 14, color: AppColors.primary),
                SizedBox(width: AppSpacing.xs),
                Text(
                  'AI suggested actions',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => widget.onNavigate(1),
              child: const Text(
                'View all',
                style: TextStyle(color: AppColors.primary, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in displayItems)
                _AiActionCard(
                  item: item,
                  onTap: () => widget.onNavigate(1),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
