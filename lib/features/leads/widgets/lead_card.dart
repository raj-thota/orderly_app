import 'package:flutter/material.dart';
import 'package:orderly_app/core/utils/lead_ai.dart';
import 'package:orderly_app/shared/components/entry_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class LeadCard extends StatelessWidget {
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

  /// 📞 CALL
  Future<void> _makeCall(BuildContext context) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Calling...")),
    );

    final url = Uri.parse("tel:$cleanPhone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  /// 💬 WHATSAPP
  Future<void> _openWhatsApp() async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse("https://wa.me/$cleanPhone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// 📅 FOLLOW-UP FLOW (date + note)
  Future<void> _handleFollowUp(BuildContext context) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selectedDate == null) return;

    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add follow-up note"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Eg: Call again, send price...",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Skip"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    await onFollowUp?.call(
      controller.text.trim().isEmpty ? "Follow-up" : controller.text.trim(),
      selectedDate,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text("Follow-up set for ${selectedDate.day}/${selectedDate.month}"),
      ),
    );
  }

  String _intentLabel(String intent) {
    switch (intent) {
      case "order":
        return "Order";
      case "follow_up":
        return "Follow-up";
      default:
        return "Inquiry";
    }
  }

  Color _intentColor(String intent) {
    switch (intent) {
      case "order":
        return Colors.green;
      case "follow_up":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// ✨ PREMIUM BUTTON
// ONLY CHANGES SHOWN — rest same imports

Widget _button(String label, IconData icon, Color color, VoidCallback onTap) {
  return Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text("Edit"),
              onTap: () {
                Navigator.pop(context);
                onEdit?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete"),
              onTap: () {
                Navigator.pop(context);
                onDelete?.call();
              },
            ),
          ],
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
      "date": date,
      "created_at": createdAt,
    });

    final priority = getPriorityLabel(score);
    final suggestion = getSuggestion({"msg": message});

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EntryDetailScreen(
                  entry: {
                    "name": name,
                    "msg": message,
                    "phone": phone,
                    "intent": intent,
                    "date": date,
                    "status": status,
                    "created_at": createdAt,
                  },
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// HEADER
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.deepPurple.shade50,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : "C",
                        style: const TextStyle(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),

                          const SizedBox(height: 4),

                          Wrap(
                            spacing: 6,
                            children: [
                              if (intent != null)
                                _badge(_intentLabel(intent!),
                                    _intentColor(intent!)),
                              _badge(priority, Colors.grey),
                            ],
                          ),
                        ],
                      ),
                    ),

                    IconButton(
                      icon: const Icon(Icons.more_vert, size: 20),
                      onPressed: () => _showActions(context),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                /// MESSAGE
                Text(message, style: const TextStyle(color: Colors.grey)),

                const SizedBox(height: 8),

                /// SUGGESTION (highlighted)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb,
                          size: 16, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          suggestion,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                /// BUTTONS
                Row(
                  children: [
                    _button("Chat", Icons.chat, Colors.green, _openWhatsApp),
                    const SizedBox(width: 8),
                    _button("Call", Icons.phone, Colors.deepPurple,
                        () => _makeCall(context)),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    _button("Follow", Icons.schedule, Colors.orange,
                        () => _handleFollowUp(context)),
                    const SizedBox(width: 8),
                    _button("Convert", Icons.check_circle, Colors.green,
                        onDone ?? () {}),
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