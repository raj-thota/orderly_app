import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/conversations/presentation/customer_workspace_screen.dart';
import 'package:orderly_app/features/focus/presentation/focus_mode_route.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';
import 'package:orderly_app/shared/widgets/approval_tile.dart';

class MyWorkScreen extends ConsumerStatefulWidget {
  const MyWorkScreen({super.key});

  @override
  ConsumerState<MyWorkScreen> createState() => _MyWorkScreenState();
}

class _MyWorkScreenState extends ConsumerState<MyWorkScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workItemsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workItemsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text(
          'My Work',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 0),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              onPressed: () => FocusMode.start(context),
              child: const Text(
                'Start My Work',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(workItemsProvider.notifier).load(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'All (${state.pendingCount})'),
            Tab(text: 'High (${state.highItems.length})'),
            Tab(text: 'Medium (${state.mediumItems.length})'),
            Tab(text: 'Low (${state.lowItems.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ItemList(items: state.items),
          _ItemList(items: state.highItems),
          _ItemList(items: state.mediumItems),
          _ItemList(items: state.lowItems),
        ],
      ),
    );
  }
}

class _ItemList extends ConsumerWidget {
  const _ItemList({required this.items});
  final List<AiWorkItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 48, color: AppColors.success),
            SizedBox(height: AppSpacing.md),
            Text("You're all caught up!",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            SizedBox(height: 6),
            Text('No pending work items.',
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(workItemsProvider.notifier).load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: items.length,
        separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, i) {
          final item = items[i];
          return ApprovalTile(
            item: item,
            onTap: () => _openWorkspace(context, item),
            onActionTap: () => _handleAction(context, ref, item),
            onDismiss: () =>
                ref.read(workItemsProvider.notifier).dismiss(item.id),
          );
        },
      ),
    );
  }

  void _openWorkspace(BuildContext context, AiWorkItem item) {
    if (item.customerId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerWorkspaceScreen(
          customerId: item.customerId!,
          customerName: item.customerName ?? 'Customer',
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, AiWorkItem item) {
    // Open workspace with draft-reply pre-triggered for this kind.
    _openWorkspace(context, item);
  }
}
