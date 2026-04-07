import 'package:flutter/material.dart';
import 'package:orderly_app/core/services/lead_navigation_service.dart';
import 'package:orderly_app/core/utils/lead_ai.dart';
import 'package:url_launcher/url_launcher.dart';

class LeadCard extends StatelessWidget {
  final String id;
  final String name;
  final String message;
  final String phone;
  final bool isOverdue;

  final String? intent;
  final DateTime? date;
  final String? status;
  final DateTime? createdAt;

  final Future<void> Function(String note, DateTime date)? onFollowUp;
  final VoidCallback? onDone;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const LeadCard({
    super.key,
    required this.id,
    required this.name,
    required this.message,
    required this.phone,
    required this.isOverdue,
    this.intent,
    this.date,
    this.status,
    this.createdAt,
    this.onFollowUp,
    this.onDone,
    this.onEdit,
    this.onDelete,
  });

  Future<void> _makeCall(BuildContext context) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) return;

    final url = Uri.parse("tel:$cleanPhone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _openWhatsApp() async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) return;

    final url = Uri.parse("https://wa.me/$cleanPhone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleFollowUp(BuildContext context) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selectedDate == null || !context.mounted) return;

    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Schedule follow-up"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Add a quick note",
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    await onFollowUp?.call(
      controller.text.trim().isEmpty ? "Follow-up" : controller.text.trim(),
      selectedDate,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Follow-up set for ${_formatShortDate(selectedDate)}"),
      ),
    );
  }

  Future<void> _confirmConvert(BuildContext context) async {
    if (onDone == null) return;

    final shouldConvert = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Convert to order?"),
        content: Text("$name will be marked as converted to an order."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text("Convert"),
          ),
        ],
      ),
    );

    if (shouldConvert != true || !context.mounted) return;

    onDone?.call();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("$name converted to order")));
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("Edit lead"),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onEdit?.call();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Delete lead"),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _intentLabel(String value) {
    switch (value) {
      case "order":
        return "Order";
      case "follow_up":
        return "Follow-up";
      case "high":
        return "High intent";
      default:
        return "Inquiry";
    }
  }

  Color _intentColor(String value) {
    switch (value) {
      case "order":
        return const Color(0xFF0F9D58);
      case "follow_up":
        return const Color(0xFFE08B00);
      case "high":
        return const Color(0xFFB85C00);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _statusLabel() {
    switch ((status ?? "").toLowerCase()) {
      case "follow":
        return "Follow-up";
      case "closed":
        return "Order";
      case "new":
        return "New";
      default:
        return status == null || status!.trim().isEmpty ? "Open" : status!;
    }
  }

  Color _statusColor() {
    switch ((status ?? "").toLowerCase()) {
      case "follow":
        return const Color(0xFFCC7A00);
      case "closed":
        return const Color(0xFF0F9D58);
      case "new":
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _priorityLabel(int score) {
    if (score > 70) return "🔥 High";
    if (score > 40) return "⚡ Warm";
    return "🧊 Cold";
  }

  Color _priorityColor(int score) {
    if (score > 70) return const Color(0xFFB85C00);
    if (score > 40) return const Color(0xFF6C4ED9);
    return const Color(0xFF64748B);
  }

  String _formatShortDate(DateTime value) {
    const months = <String>[
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];

    return "${value.day} ${months[value.month - 1]}";
  }

  Widget _badge(String text, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? color : color.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    final isEnabled = onTap != null;

    return Expanded(
      child: Opacity(
        opacity: isEnabled ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              height: 40,
              decoration: BoxDecoration(
                color: filled ? color : color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: filled ? color : color.withValues(alpha: 0.20),
                ),
                boxShadow: filled
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: filled ? Colors.white : color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: filled ? Colors.white : color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final score = getLeadScore({
      "msg": message,
      "intent": intent,
      "status": status,
      "follow_up_date": date,
      "created_at": createdAt,
    });

    final suggestion = getSuggestion({"msg": message});
    final priorityColor = _priorityColor(score);
    final statusColor = _statusColor();
    final cardAccent = isOverdue
        ? Colors.red.shade600
        : score > 70
        ? priorityColor
        : const Color(0xFFE5E7EB);

    final backgroundColor = isOverdue
        ? const Color(0xFFFFF7F7)
        : score > 70
        ? const Color(0xFFFFFAF2)
        : Colors.white;

    final displayName = name.trim().isEmpty ? "Unknown Lead" : name.trim();
    final trimmedMessage = message.trim().isEmpty
        ? "No message available"
        : message.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.of(context).push(
              LeadNavigationService.leadDetailRoute({
                "id": id,
                "name": name,
                "msg": message,
                "phone": phone,
                "intent": intent,
                "status": status,
                "follow_up_date": date?.toIso8601String(),
                "created_at": createdAt?.toIso8601String(),
              }),
            );
          },
          child: Ink(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isOverdue
                    ? Colors.red.shade200
                    : cardAccent.withValues(alpha: score > 70 ? 0.35 : 0.12),
                width: isOverdue || score > 70 ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: priorityColor.withValues(
                    alpha: isOverdue
                        ? 0.10
                        : score > 40
                        ? 0.08
                        : 0.04,
                  ),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              priorityColor.withValues(alpha: 0.16),
                              priorityColor.withValues(alpha: 0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            displayName[0].toUpperCase(),
                            style: TextStyle(
                              color: priorityColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                _badge(_statusLabel(), statusColor),
                                _badge(
                                  _priorityLabel(score),
                                  priorityColor,
                                  filled: score > 70 && !isOverdue,
                                ),
                                if (intent != null && intent!.trim().isNotEmpty)
                                  _badge(
                                    _intentLabel(intent!),
                                    _intentColor(intent!),
                                  ),
                                if (isOverdue)
                                  _badge(
                                    date != null
                                        ? "Overdue · ${_formatShortDate(date!)}"
                                        : "Overdue",
                                    Colors.red.shade600,
                                    filled: true,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showActions(context),
                        icon: const Icon(Icons.more_horiz_rounded),
                        splashRadius: 20,
                        color: const Color(0xFF6B7280),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.76),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      trimmedMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isOverdue
                              ? Icons.priority_high_rounded
                              : Icons.auto_awesome_rounded,
                          size: 15,
                          color: isOverdue
                              ? Colors.red.shade600
                              : priorityColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isOverdue
                                ? "Needs attention now"
                                : "AI suggests: $suggestion",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isOverdue
                                  ? Colors.red.shade700
                                  : const Color(0xFF1F2937),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _actionButton(
                        label: "Follow-up",
                        icon: Icons.schedule_rounded,
                        color: const Color(0xFFE08B00),
                        onTap: onFollowUp == null
                            ? null
                            : () => _handleFollowUp(context),
                      ),
                      const SizedBox(width: 10),
                      _actionButton(
                        label: "Call",
                        icon: Icons.call_rounded,
                        color: const Color(0xFF6C4ED9),
                        onTap: phone.trim().isEmpty
                            ? null
                            : () => _makeCall(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _actionButton(
                        label: "WhatsApp",
                        icon: Icons.chat_bubble_rounded,
                        color: const Color(0xFF0F9D58),
                        onTap: phone.trim().isEmpty ? null : _openWhatsApp,
                      ),
                      const SizedBox(width: 10),
                      _actionButton(
                        label: "Convert",
                        icon: Icons.check_circle_rounded,
                        color: const Color(0xFF0F9D58),
                        onTap: onDone == null
                            ? null
                            : () => _confirmConvert(context),
                        filled: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
