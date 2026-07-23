import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/capture/presentation/capture_sheet.dart';
import 'package:orderly_app/features/catalog/presentation/catalog_screen.dart';
import 'package:orderly_app/features/conversations/presentation/customer_workspace_screen.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/invoices/presentation/invoices_screen.dart';
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/presentation/order_detail_screen.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/data/subscription.dart';
import 'package:orderly_app/features/subscription/presentation/subscription_screen.dart';
import 'package:orderly_app/features/today/data/brief_narrative.dart';
import 'package:orderly_app/features/today/data/home_insight.dart';
import 'package:orderly_app/features/today/data/recent_activity.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';
import 'package:orderly_app/features/focus/presentation/focus_mode_route.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

/// Google/profile photo if present, else null (caller renders initials).
ImageProvider? profileAvatarImage(String? avatarUrl) {
  if (avatarUrl == null || avatarUrl.isEmpty) return null;
  return NetworkImage(avatarUrl);
}

/// Soft elevation for cards — replaces hairline borders for a calmer surface.
const List<BoxShadow> _cardShadow = [
  BoxShadow(
    color: Color(0x0D000000), // black at 5%
    blurRadius: 14,
    offset: Offset(0, 4),
  ),
];

String _timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inDays >= 1) return '${diff.inDays}d ago';
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
  return 'Just now';
}

// ─── Pressable (scale-on-tap) ─────────────────────────────────────────────────

/// Wraps a card in a subtle press-scale animation without changing its layout.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

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

// ─── Brief check-list item ────────────────────────────────────────────────────

/// One line of the AI brief: a small circular check chip + the task text,
/// rendered on the gradient hero card.
class _BriefCheckItem extends StatelessWidget {
  const _BriefCheckItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.icon,
    this.trailingLabel,
    this.onTrailingTap,
  });

  final String title;
  final IconData? icon;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        if (trailingLabel != null)
          TextButton(
            onPressed: onTrailingTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              trailingLabel!,
              style: const TextStyle(color: AppColors.primary, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

// ─── Work row (compact task) ──────────────────────────────────────────────────

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.item, required this.onTap});

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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _priorityColor(item.priority),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                focusLabel(item),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${estimatedMinutesFor(item)} min',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Insight card ─────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.onTap});

  final HomeInsight insight;
  final VoidCallback onTap;

  (IconData, Color) _style(HomeInsightKind kind) {
    switch (kind) {
      case HomeInsightKind.collectPayments:
        return (Icons.currency_rupee_rounded, AppColors.danger);
      case HomeInsightKind.followUpsDue:
        return (Icons.schedule_rounded, AppColors.warning);
      case HomeInsightKind.newOrders:
        return (Icons.shopping_bag_outlined, AppColors.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style(insight.kind);
    return _Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.aiSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    insight.evidence,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${insight.cta} →',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Snapshot tile ────────────────────────────────────────────────────────────

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick action button ──────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: _cardShadow,
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Today screen ─────────────────────────────────────────────────────────────

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, required this.onNavigate});

  final void Function(int tab) onNavigate;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(eventServiceProvider).track('brief_view');
      ref.read(workItemsProvider.notifier).load();
    });
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _dateEyebrow(DateTime now) =>
      '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}'
          .toUpperCase();

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

  Widget _buildProfileAvatar() {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final avatarUrl = profile?['avatar_url'] as String?;
    final name = (profile?['business_name'] as String?) ?? '';
    final image = profileAvatarImage(avatarUrl);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: GestureDetector(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Soft brand ring + shadow lifts the avatar off the bar.
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.aiAccent, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  key: const Key('today_profile_avatar'),
                  radius: 15,
                  backgroundColor: AppColors.surface,
                  backgroundImage: image,
                  child: image != null
                      ? null
                      : Text(
                          _initialLetter(name),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
              // Business "online" status dot.
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                ),
              ),
            ],
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
    final name = ref.watch(userProfileProvider).value?['business_name'] ?? '';
    final now = DateTime.now();
    final brief = buildTodayBrief(
      orders: orders,
      enquiries: enquiries,
      now: now,
    );
    final workState = ref.watch(workItemsProvider);
    final insights = buildHomeInsights(brief, now: now);
    final activity = buildRecentActivity(orders);

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
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1 — Greeting
                _buildGreeting(name, now),
                const SizedBox(height: AppSpacing.lg),

                // Plan nudge: only when the trial is about to end or has
                // ended — the one moment the paywall is actually relevant.
                const _PlanNudge(),

                // 2 — AI brief (hero)
                _buildHeroBrief(brief, workState, now),

                // 3 — Today's work queue
                if (workState.items.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _buildWorkQueue(workState),
                ],

                // 4 — AI insights
                if (insights.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _buildInsights(insights),
                ],

                // 5 — Business snapshot
                const SizedBox(height: AppSpacing.xl),
                _buildSnapshot(brief),

                // 6 — Recent activity
                if (activity.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _buildActivity(activity),
                ],

                // 7 — Quick actions
                const SizedBox(height: AppSpacing.xl),
                _buildQuickActions(),

                // Clearance for the docked FAB.
                const SizedBox(height: AppSpacing.xxl * 2),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo is the "C" of the wordmark; the rest stays as text.
          const Image(image: AssetImage('assets/logo/logo.png'), height: 40),
          // Pull the text left to close the transparent padding baked into the
          // logo PNG so "Closr" reads as one word.
          Transform.translate(
            offset: const Offset(-6, 0),
            child: const Text(
              'Closr',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        Stack(
          children: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(
                Icons.notifications_outlined,
                color: AppColors.textPrimary,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
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
                    color: AppColors.danger,
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
          _dateEyebrow(now),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // "Good afternoon 👋," stays put; only the business name ellipsises,
        // so the whole greeting holds one line.
        Row(
          children: [
            Text(
              name.isEmpty ? '${_greeting(now)} 👋' : '${_greeting(now)} 👋,',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildHeroBrief(
    TodayBrief brief,
    WorkItemsState workState,
    DateTime now,
  ) {
    final narrative = buildBriefNarrative(
      brief: brief,
      items: workState.items,
      now: now,
    );
    final body = workState.loading && workState.items.isEmpty
        ? 'Pulling together your day…'
        : narrative.body;
    final hasChecklist = narrative.bullets.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.briefGradientStart, AppColors.briefGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x335B4FE9), // brand glow, 20%
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 13, color: Colors.white70),
              const SizedBox(width: AppSpacing.xs),
              Text(
                narrative.eyebrow,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
          if (hasChecklist) ...[
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < narrative.bullets.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _BriefCheckItem(text: narrative.bullets[i]),
            ],
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (workState.items.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: Colors.white70,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${workState.items.length} task${workState.items.length == 1 ? '' : 's'} · about ${estimatedMinutes(workState.items)} min',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // CTA and the friendly companion share one line: the button takes
          // the width it needs, the robot sits just after it.
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  onPressed: () => FocusMode.start(context),
                  child: const Text(
                    'Start My Work →',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Image.asset(
                'assets/robo.png',
                width: 60,
                height: 72,
                fit: BoxFit.contain,
                errorBuilder: (ctx, e, stack) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkQueue(WorkItemsState workState) {
    final displayItems = workState.items.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: "Today's Work",
          icon: Icons.auto_awesome,
          trailingLabel: 'View all (${workState.pendingCount})',
          onTrailingTap: () => widget.onNavigate(1),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: _cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < displayItems.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: AppSpacing.lg,
                      color: AppColors.border,
                    ),
                  _WorkRow(
                    item: displayItems[i],
                    onTap: () => _openWorkspace(displayItems[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                // Whole pending queue, matching the hero meta and "View all".
                '🕒 About ${estimatedMinutes(workState.items)} min',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '✓ ${workState.completedCount} / ${workState.totalCount} completed',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsights(List<HomeInsight> insights) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'AI insights', icon: Icons.auto_awesome),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < insights.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _InsightCard(
            insight: insights[i],
            onTap: () => widget.onNavigate(insights[i].targetTab),
          ),
        ],
      ],
    );
  }

  Widget _buildSnapshot(TodayBrief brief) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Business snapshot'),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _SnapshotTile(
                key: const Key('snap_orders'),
                icon: Icons.shopping_bag_outlined,
                iconColor: AppColors.info,
                label: 'Orders today',
                value: '${brief.ordersToday}',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SnapshotTile(
                key: const Key('snap_revenue'),
                icon: Icons.currency_rupee_rounded,
                iconColor: AppColors.success,
                label: 'Revenue today',
                value: Money.inr(brief.revenueToday),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _SnapshotTile(
                key: const Key('snap_outstanding'),
                icon: Icons.hourglass_bottom_rounded,
                iconColor: AppColors.danger,
                label: 'Outstanding',
                value: Money.inr(brief.outstanding),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SnapshotTile(
                key: const Key('snap_followups'),
                icon: Icons.chat_bubble_outline_rounded,
                iconColor: AppColors.warning,
                label: 'Follow-ups due',
                value: '${brief.dueFollowUps}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActivity(List<ActivityEntry> activity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Recent activity'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: _cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < activity.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: AppSpacing.lg,
                      color: AppColors.border,
                    ),
                  _buildActivityRow(activity[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityRow(ActivityEntry entry) {
    final isPayment = entry.kind == ActivityKind.paymentReceived;
    final who =
        entry.order.customerName ??
        (entry.order.orderNumber != null
            ? 'Order #${entry.order.orderNumber}'
            : 'Customer');
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(order: entry.order),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (isPayment ? AppColors.success : AppColors.info)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPayment
                    ? Icons.check_circle_outline_rounded
                    : Icons.shopping_bag_outlined,
                color: isPayment ? AppColors.success : AppColors.info,
                size: 18,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPayment ? 'Payment received' : 'New order',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$who · ${_timeAgo(entry.at)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (entry.amount != null)
              Text(
                isPayment
                    ? '+${Money.inr(entry.amount!)}'
                    : Money.inr(entry.amount!),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isPayment ? AppColors.success : AppColors.textPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Quick actions'),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.add_shopping_cart_rounded,
                label: 'New sale',
                onTap: () => CaptureSheet.show(context),
              ),
            ),
            Expanded(
              child: _QuickAction(
                icon: Icons.currency_rupee_rounded,
                label: 'Payments',
                onTap: () => widget.onNavigate(2),
              ),
            ),
            Expanded(
              child: _QuickAction(
                icon: Icons.grid_view_rounded,
                label: 'Catalog',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CatalogScreen()),
                ),
              ),
            ),
            Expanded(
              child: _QuickAction(
                icon: Icons.receipt_long_outlined,
                label: 'Invoices',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InvoicesScreen()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact upgrade nudge shown only when it matters: trial ending within
/// 3 days, or trial over (AI paused). Hidden for active subscribers and
/// through most of the trial so the home screen never feels like an ad.
class _PlanNudge extends ConsumerWidget {
  const _PlanNudge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    if (sub == null) return const SizedBox.shrink();

    final String text;
    switch (sub.entitlement) {
      case EntitlementStatus.active:
        return const SizedBox.shrink();
      case EntitlementStatus.trialing:
        final days = sub.trialDaysLeft;
        if (days > 3) return const SizedBox.shrink();
        text =
            'Your Pro trial ends in $days day${days == 1 ? '' : 's'} — '
            'keep the AI working for you.';
      case EntitlementStatus.gated:
        text =
            'Your trial has ended — AI is paused. '
            'Core features stay free.';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          key: const Key('today_plan_nudge'),
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
