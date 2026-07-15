import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/conversations/presentation/customer_workspace_screen.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';
import 'package:orderly_app/features/today/data/ai_card_action.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

/// Google/profile photo if present, else null (caller renders initials).
ImageProvider? profileAvatarImage(String? avatarUrl) {
  if (avatarUrl == null || avatarUrl.isEmpty) return null;
  return NetworkImage(avatarUrl);
}

// ─── Nudge data ──────────────────────────────────────────────────────────────

class _NudgeData {
  const _NudgeData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.cardColor,
    required this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color cardColor;
  final Color iconColor;
}

// ─── Pressable (scale-on-tap) ─────────────────────────────────────────────────

/// Wraps a card in a subtle press-scale animation without changing its layout.
class _Pressable extends StatefulWidget {
  const _Pressable({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ─── Stat tile ───────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.highlightColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: highlightColor.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: highlightColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
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
      case 'high': return AppColors.danger;
      case 'medium': return AppColors.warning;
      case 'low': return AppColors.success;
      default: return AppColors.textSecondary;
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

  /// Action-first headline so the user reads WHAT to do before WHO it's for.
  String _actionHeadline(String kind) {
    switch (kind) {
      case 'payment_reminder':
      case 'overdue_payment':
        return 'Collect Payment';
      case 'follow_up':
      case 'call':
        return 'Follow Up';
      case 'share_catalog':
      case 'offer':
        return 'Share Offer';
      default:
        return 'Send Update';
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
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 1) return '${diff.inDays} days ago';
    if (diff.inHours >= 1) return '${diff.inHours} hours ago';
    return 'Today';
  }

  String _subtitle() {
    final time = _timeAgo(item.createdAt);
    final String? prefix;
    if (item.orderId != null) {
      prefix = 'Order #${item.orderId}';
    } else if (item.leadId != null) {
      prefix = 'Hot lead';
    } else {
      prefix = null;
    }
    if (prefix != null && time.isNotEmpty) return '$prefix • $time';
    return prefix ?? time;
  }

  @override
  Widget build(BuildContext context) {
    return _Pressable(
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
                      Flexible(
                        child: Text(
                          _actionHeadline(item.kind),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _priorityColor(item.priority)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          _priorityLabel(item.priority),
                          style: TextStyle(
                            color: _priorityColor(item.priority),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.customerName ?? '—',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
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
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: Text(_actionLabel(item.kind)),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.sm),
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
    final name = item.customerName ?? 'this customer';
    switch (item.kind) {
      case 'payment_reminder':
      case 'overdue_payment':
        return _CardConfig(
          icon: Icons.currency_rupee_rounded,
          color: AppColors.danger,
          desc: '$name has a pending payment. Send a gentle nudge.',
          cta: 'Send Reminder →',
        );
      case 'follow_up':
      case 'call':
        return _CardConfig(
          icon: Icons.phone_outlined,
          color: AppColors.primary,
          desc: '$name is waiting to hear back. Follow up now.',
          cta: 'Follow Up →',
        );
      case 'share_catalog':
      case 'offer':
        return _CardConfig(
          icon: Icons.card_giftcard_outlined,
          color: AppColors.warning,
          desc: 'Win $name back with a quick offer.',
          cta: 'Share Offer →',
        );
      default:
        return _CardConfig(
          icon: Icons.message_outlined,
          color: AppColors.aiAccent,
          desc: 'Reach out to $name before they go quiet.',
          cta: 'Message →',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config(item);
    return _Pressable(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cfg.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(cfg.icon, color: cfg.color, size: 18),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    cfg.desc,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                cfg.cta,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
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
  int _nudgePage = 0;
  int _nudgeCount = 0;
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(eventServiceProvider).track('brief_view');
      ref.read(workItemsProvider.notifier).load();
    });
    _nudgeTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_nudgeCount > 1 && mounted) {
        setState(() {
          _nudgePage = (_nudgePage + 1) % _nudgeCount;
        });
      }
    });
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    super.dispose();
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _initialLetter(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  /// Opens the full customer workspace for a work item.
  void _openWorkspace(AiWorkItem item) {
    if (item.customerId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerWorkspaceScreen(
          customerId: item.customerId!,
          customerName: item.customerName ?? 'Customer',
          phone: item.phone,
        ),
      ),
    );
  }

  /// Runs the direct CTA action for an AI card (call / WhatsApp / workspace).
  Future<void> _runCardAction(AiWorkItem item) async {
    final action = resolveAiCardAction(item);
    if (action.type == AiCardActionType.workspace) {
      _openWorkspace(item);
      return;
    }
    try {
      final launched =
          await launchUrl(action.uri!, mode: LaunchMode.externalApplication);
      if (!launched && mounted) _openWorkspace(item);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that app')),
        );
      }
    }
  }

  Widget _buildProfileAvatar() {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final avatarUrl = profile?['avatar_url'] as String?;
    final name = (profile?['business_name'] as String?) ?? '';
    final image = profileAvatarImage(avatarUrl);
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ),
        child: CircleAvatar(
          key: const Key('today_profile_avatar'),
          radius: 16,
          backgroundColor: AppColors.aiSurface,
          backgroundImage: image,
          child: image != null
              ? null
              : Text(
                  _initialLetter(name),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
        ),
      ),
    );
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
            '${brief.dueFollowUps} follow-up${brief.dueFollowUps == 1 ? '' : 's'} need your attention',
        subtitle: 'Reply before they lose interest',
        onTap: () => widget.onNavigate(1),
        cardColor: const Color(0xFFFFF3E0),
        iconColor: const Color(0xFFE65100),
      ));
    }
    if (brief.outstanding > 0) {
      nudges.add(_NudgeData(
        icon: Icons.currency_rupee_rounded,
        title: '${Money.inr(brief.outstanding)} outstanding payments',
        subtitle: 'Send reminders and get paid',
        onTap: () => widget.onNavigate(2),
        cardColor: const Color(0xFFFFEBEE),
        iconColor: const Color(0xFFC62828),
      ));
    }
    if (brief.ordersToday > 0) {
      nudges.add(_NudgeData(
        icon: Icons.shopping_bag_outlined,
        title: '${brief.ordersToday} new order(s) placed today',
        subtitle: 'Review and confirm them',
        onTap: () => widget.onNavigate(2),
        cardColor: const Color(0xFFE8F5E9),
        iconColor: const Color(0xFF2E7D32),
      ));
    }

    // Nudge page desync guard + sync count for auto-advance
    _nudgeCount = nudges.length;
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Greeting
                _buildGreeting(name, now),
                const SizedBox(height: AppSpacing.lg),

                // Glance card
                _buildGlanceCard(brief, workState.pendingCount),
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
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(int pendingCount) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      leading: _buildProfileAvatar(),
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

  Widget _buildGlanceCard(TodayBrief brief, int pendingCount) {
    final briefLine = pendingCount > 0
        ? '🤖 You have $pendingCount task${pendingCount == 1 ? '' : 's'} waiting today.'
        : '🤖 All caught up — nothing needs you right now.';
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Today at a glance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Today',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_down,
                        color: Colors.white, size: 16),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            briefLine,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _StatRow(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Follow-ups due',
                      value: '${brief.dueFollowUps}',
                      highlightColor: const Color(0xFFFF8A80),
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
                    _StatRow(
                      icon: Icons.shopping_bag_outlined,
                      label: 'Orders today',
                      value: '${brief.ordersToday}',
                      highlightColor: const Color(0xFF69F0AE),
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
                    _StatRow(
                      icon: Icons.currency_rupee_rounded,
                      label: 'Revenue today',
                      value: brief.revenueToday > 0
                          ? Money.inr(brief.revenueToday)
                          : '₹0',
                      highlightColor: const Color(0xFFFFD54F),
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
                    _StatRow(
                      icon: Icons.layers_outlined,
                      label: 'Outstanding',
                      value: Money.inr(brief.outstanding),
                      highlightColor: const Color(0xFF82B1FF),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Image.asset(
                'assets/robo.png',
                width: 104,
                height: 150,
                fit: BoxFit.contain,
                errorBuilder: (ctx, e, stack) => const SizedBox(width: 104),
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
                "Start Today's Tasks →",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNudgeCarousel(List<_NudgeData> nudges) {
    final nudge = nudges[_nudgePage];
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 70,
            width: double.infinity,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOut,
                    )),
                    child: child,
                  ),
                );
              },
              child: _Pressable(
                key: ValueKey(_nudgePage),
                onTap: nudge.onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: nudge.iconColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(nudge.icon, color: nudge.iconColor, size: 22),
                      ),
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
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              nudge.subtitle,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondary, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (nudges.length > 1) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(nudges.length, (i) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _nudgePage == i
                      ? AppColors.primary
                      : AppColors.border,
                  shape: BoxShape.circle,
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
            onTap: () => _openWorkspace(item),
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
                  onTap: () => _runCardAction(item),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
