import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/conversations/controller/conversation_provider.dart';
import 'package:orderly_app/features/conversations/data/ai_summary.dart';
import 'package:orderly_app/shared/widgets/ai_card.dart';
import 'package:orderly_app/shared/widgets/chat_bubble.dart';

class CustomerWorkspaceScreen extends ConsumerStatefulWidget {
  const CustomerWorkspaceScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.phone,
  });

  final String customerId;
  final String customerName;
  final String? phone;

  @override
  ConsumerState<CustomerWorkspaceScreen> createState() =>
      _CustomerWorkspaceScreenState();
}

class _CustomerWorkspaceScreenState
    extends ConsumerState<CustomerWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(conversationNotifierProvider(widget.customerId).notifier)
          .loadMessages(widget.customerId);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(
          widget.customerName,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        actions: [
          if (widget.phone != null)
            IconButton(
              icon: const Icon(Icons.phone_outlined),
              onPressed: () =>
                  launchUrl(Uri.parse('tel:${widget.phone}')),
            ),
          if (widget.phone != null)
            IconButton(
              icon: const Icon(Icons.chat_rounded),
              onPressed: () =>
                  launchUrl(Uri.parse('https://wa.me/91${widget.phone}')),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Chat'),
            Tab(text: 'Summary'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ChatTab(customerId: widget.customerId),
          _SummaryTab(customerId: widget.customerId),
        ],
      ),
    );
  }
}

// ─── Chat tab ─────────────────────────────────────────────────────────────────

class _ChatTab extends ConsumerWidget {
  const _ChatTab({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationNotifierProvider(customerId));

    return Column(
      children: [
        Expanded(
          child: state.loading && state.messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: state.messages.length,
                  itemBuilder: (_, i) {
                    final msg = state.messages[i];
                    return ChatBubble(
                      body: msg.body,
                      direction: msg.direction,
                      isAiSend: msg.isAiSend,
                    );
                  },
                ),
        ),
        if (state.draft != null) _DraftBar(customerId: customerId),
        _ChatActions(customerId: customerId),
      ],
    );
  }
}

class _ChatActions extends ConsumerWidget {
  const _ChatActions({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationNotifierProvider(customerId));
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
      color: AppColors.surface,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: state.draftLoading
                  ? null
                  : () => ref
                      .read(conversationNotifierProvider(customerId).notifier)
                      .requestDraft(customerId, objective: 'reply'),
              icon: state.draftLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('Draft Reply'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftBar extends ConsumerWidget {
  const _DraftBar({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(conversationNotifierProvider(customerId)).draft;
    if (draft == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.aiSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.aiAccent.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 12, color: AppColors.aiAccent),
              const SizedBox(width: 4),
              const Text(
                'AI Draft',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.aiAccent,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ref
                    .read(conversationNotifierProvider(customerId).notifier)
                    .clearDraft(),
                child: const Icon(Icons.close,
                    size: 16, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(draft.message,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _approve(context, ref, draft.message),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Approve & Send'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(
      BuildContext context, WidgetRef ref, String message) async {
    final notifier =
        ref.read(conversationNotifierProvider(customerId).notifier);
    // Log the ai_send message first (optimistic).
    await notifier.logAiSend(customerId, message);
    notifier.clearDraft();
    // The customer's phone comes from the conversation; for the wa.me URL
    // we need it passed from the parent. For now, open WhatsApp app only.
    // The full wa.me URL with pre-filled message is built when phone is
    // passed via CustomerWorkspaceScreen (see §7 spec — phone from DB only).
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening WhatsApp…'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

// ─── Summary tab ──────────────────────────────────────────────────────────────

class _SummaryTab extends ConsumerStatefulWidget {
  const _SummaryTab({required this.customerId});
  final String customerId;

  @override
  ConsumerState<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<_SummaryTab> {
  AiSummary? _summary;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(customerSummaryServiceProvider);
    final s = await svc.fetch(widget.customerId);
    if (!mounted) return;
    setState(() {
      _summary = s;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final svc = ref.read(customerSummaryServiceProvider);
    final s = await svc.refresh(widget.customerId);
    if (!mounted) return;
    setState(() {
      _summary = s;
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_summary == null || !_summary!.hasSummary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No summary yet',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('Generate Summary'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      );
    }

    final s = _summary!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AiCard(
          title: 'AI SUMMARY',
          onEdit: _refresh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final bullet in s.bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle,
                          size: 5, color: AppColors.aiAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(bullet,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
              if (s.closeConfidence != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    const Text('Close confidence: ',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    Text('${(s.closeConfidence! * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.aiAccent)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
