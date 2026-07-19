import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/conversations/presentation/customer_workspace_screen.dart';
import 'package:orderly_app/features/today/data/ai_card_action.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

/// In-app notifications: the same AI work items that drive the bell badge,
/// so the count and the list always agree.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workItemsProvider.notifier).load();
    });
  }

  void _open(AiWorkItem item) {
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

  Future<void> _runAction(AiWorkItem item) async {
    final action = resolveAiCardAction(item);
    if (action.type == AiCardActionType.workspace) {
      _open(item);
      return;
    }
    try {
      final launched =
          await launchUrl(action.uri!, mode: LaunchMode.externalApplication);
      if (!launched && mounted) _open(item);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that app')),
        );
      }
    }
  }

  void _done(AiWorkItem item) {
    ref.read(workItemsProvider.notifier).markDone(item.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.customerName ?? 'Item'} marked done ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workItemsProvider);
    final high = state.highItems;
    final others = [...state.mediumItems, ...state.lowItems];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (state.items.isNotEmpty)
            IconButton(
              key: const Key('notif_mark_all_done'),
              tooltip: 'Mark all done',
              icon: const Icon(Icons.done_all_rounded),
              onPressed: () {
                ref.read(workItemsProvider.notifier).markAllDone();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Marked all done ✅')),
                  );
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(workItemsProvider.notifier).load(),
          ),
        ],
      ),
      body: state.items.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: () => ref.read(workItemsProvider.notifier).load(),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (high.isNotEmpty) ...[
                    const _SectionTitle('🔥 Urgent'),
                    const SizedBox(height: AppSpacing.sm),
                    for (final item in high) _dismissibleTile(item),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (others.isNotEmpty) ...[
                    const _SectionTitle('Needs attention'),
                    const SizedBox(height: AppSpacing.sm),
                    for (final item in others) _dismissibleTile(item),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 50, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          const Text(
            'All caught up 🎉',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'No pending work right now',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _dismissibleTile(AiWorkItem item) {
    return Dismissible(
      key: ValueKey('notif_dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.close_rounded, color: AppColors.danger),
      ),
      onDismissed: (_) {
        ref.read(workItemsProvider.notifier).dismiss(item.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dismissed')),
          );
        }
      },
      child: _NotificationTile(
        item: item,
        onTap: () => _open(item),
        onAction: () => _runAction(item),
        onDone: () => _done(item),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.onAction,
    required this.onDone,
  });

  final AiWorkItem item;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final VoidCallback onDone;

  Color get _priorityColor {
    if (item.isHigh) return AppColors.danger;
    if (item.isMedium) return AppColors.warning;
    return AppColors.textSecondary;
  }

  String get _actionLabel {
    switch (resolveAiCardAction(item).type) {
      case AiCardActionType.call:
        return 'Call';
      case AiCardActionType.whatsapp:
        return 'Message';
      case AiCardActionType.workspace:
        return 'Open';
    }
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    return name.trim()[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _priorityColor.withValues(alpha: 0.12),
                  child: Text(
                    _initials(item.customerName),
                    style: TextStyle(
                      color: _priorityColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.customerName ?? 'Customer',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (item.context != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.context!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (item.amount != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          Money.inr(item.amount!),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                      if (item.createdAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _relativeTime(item.createdAt!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  children: [
                    _MiniButton(
                      key: Key('notif_action_${item.id}'),
                      color: AppColors.primary,
                      label: _actionLabel,
                      onTap: onAction,
                    ),
                    const SizedBox(height: 6),
                    _MiniButton(
                      key: Key('notif_done_${item.id}'),
                      color: AppColors.success,
                      label: 'Done',
                      onTap: onDone,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    super.key,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
