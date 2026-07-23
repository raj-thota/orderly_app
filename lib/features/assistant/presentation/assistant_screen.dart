import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/assistant/controller/assistant_chat_provider.dart';
import 'package:orderly_app/features/assistant/data/assistant_message.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/presentation/subscription_screen.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _ctl = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() {
      final notEmpty = _ctl.text.trim().isNotEmpty;
      if (notEmpty != _canSend) setState(() => _canSend = notEmpty);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final q = _ctl.text.trim();
    if (q.isEmpty) return;
    _ctl.clear();
    await ref.read(assistantChatProvider.notifier).send(q);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantChatProvider);
    final isGated = !ref.watch(aiAccessProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Closr AI'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: state.turns.isEmpty
                ? _EmptyState()
                : _ChatList(state: state),
          ),
          if (state.thinking)
            const _TypingIndicator(),
          if (state.error != null)
            _ErrorBanner(state.error!),
          if (isGated)
            _AiGatedBar()
          else
            _InputBar(
              controller: _ctl,
              canSend: _canSend && !state.thinking,
              onSend: _send,
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy_rounded,
              size: 48, color: AppColors.aiAccent.withAlpha(160)),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Ask me anything about your business',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: const [
                _SuggestionChip('How much is outstanding?'),
                _SuggestionChip('Who are my top customers?'),
                _SuggestionChip('Any overdue follow-ups?'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
      onPressed: () {
        // No-op — user taps to copy into field (future enhancement)
      },
    );
  }
}

class _ChatList extends StatefulWidget {
  const _ChatList({required this.state});
  final AssistantState state;

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  final _scrollCtl = ScrollController();

  @override
  void didUpdateWidget(_ChatList old) {
    super.didUpdateWidget(old);
    if (widget.state.turns.length != old.state.turns.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtl.hasClients) {
          _scrollCtl.animateTo(
            _scrollCtl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollCtl,
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: widget.state.turns.length,
      itemBuilder: (_, i) {
        final turn = widget.state.turns[i];
        return _TurnWidget(turn: turn, turnIndex: i);
      },
    );
  }

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }
}

class _TurnWidget extends ConsumerWidget {
  const _TurnWidget({required this.turn, required this.turnIndex});
  final AssistantTurn turn;
  final int turnIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = turn.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _Bubble(text: turn.text, isUser: isUser),
          if (turn.proposedItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < turn.proposedItems.length; j++)
                    _ProposedItemCard(
                      item: turn.proposedItems[j],
                      itemIndex: j,
                      onApprove: () => ref
                          .read(assistantChatProvider.notifier)
                          .approveProposedItem(turn.proposedItems[j]),
                      onDismiss: () => ref
                          .read(assistantChatProvider.notifier)
                          .dismissProposedItem(turn.proposedItems[j]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.isUser});
  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: isUser ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.md),
          topRight: const Radius.circular(AppRadius.md),
          bottomLeft:
              Radius.circular(isUser ? AppRadius.md : AppRadius.sm),
          bottomRight:
              Radius.circular(isUser ? AppRadius.sm : AppRadius.md),
        ),
        border: isUser ? null : Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: isUser ? Colors.white : AppColors.textPrimary,
            fontSize: 14),
      ),
    );
  }
}

class _ProposedItemCard extends StatelessWidget {
  const _ProposedItemCard({
    required this.item,
    required this.itemIndex,
    required this.onApprove,
    required this.onDismiss,
  });

  final ProposedWorkItem item;
  final int itemIndex;
  final VoidCallback onApprove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.aiSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.aiAccent.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: AppColors.aiAccent),
              const SizedBox(width: AppSpacing.xs),
              Text(item.customerName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontSize: 13)),
              const Spacer(),
              _PriorityBadge(item.priority),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(item.draftMessage,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              FilledButton(
                key: Key('approve_work_item_$itemIndex'),
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Approve'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                key: Key('dismiss_work_item_$itemIndex'),
                onPressed: onDismiss,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge(this.priority);
  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'high' => AppColors.danger,
      'medium' => AppColors.warning,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(priority,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('assistant_typing_indicator'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      alignment: Alignment.centerLeft,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.aiAccent,
              backgroundColor: AppColors.border,
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Text('Thinking…',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.danger.withAlpha(20),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Text(message,
          style: const TextStyle(
              color: AppColors.danger, fontSize: 12)),
    );
  }
}

class _AiGatedBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Closr AI is a Pro feature',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            FilledButton(
              key: const Key('ai_gated_upgrade'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SubscriptionScreen()),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
              child: const Text('Upgrade'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ask about your customers, orders, payments…',
                  hintStyle: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                ),
                onSubmitted: (_) {
                  if (canSend) onSend();
                },
              ),
            ),
            IconButton(
              key: const Key('assistant_send'),
              tooltip: 'Send',
              onPressed: canSend ? onSend : null,
              icon: const Icon(Icons.send_rounded),
              color: AppColors.primary,
              disabledColor: AppColors.border,
            ),
          ],
        ),
      ),
    );
  }
}
