import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/utils/message_parser.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:orderly_app/shared/widgets/activity_timeline.dart';
import 'package:url_launcher/url_launcher.dart';

class EntryDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> entry;

  const EntryDetailScreen({super.key, required this.entry});

  Future<void> _call(String phone) async {
    final url = Uri.parse("tel:$phone");
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _whatsapp(String phone) async {
    final url = Uri.parse("https://wa.me/$phone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDate(DateTime d) => "${d.day}/${d.month}/${d.year}";

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  Map<String, dynamic> _ai(Map<String, dynamic> lead) {
    final parsed = MessageParser.parse(lead["msg"] ?? "");
    final intent = parsed["intent"];
    final items = parsed["items"] ?? [];

    String summary;
    List<Map<String, dynamic>> actions = [];

    if (intent == "order") {
      summary = "Customer ready to place order";
      actions = [
        {"label": "Confirm Order", "type": "done"},
        {"label": "Send Invoice", "type": "whatsapp"},
      ];
    } else if (intent == "follow_up") {
      summary = "Follow-up required soon";
      actions = [
        {"label": "Follow-up Now", "type": "follow"},
        {"label": "Call Customer", "type": "call"},
      ];
    } else {
      summary = "New inquiry. Needs engagement";
      actions = [
        {"label": "Send Details", "type": "whatsapp"},
        {"label": "Call Customer", "type": "call"},
      ];
    }

    if (items.isNotEmpty) {
      actions.add({"label": "Verify Items", "type": "follow"});
    }

    return {"summary": summary, "actions": actions};
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsControllerProvider);
    final controller = ref.read(leadsControllerProvider.notifier);

    final liveLead = leads.firstWhere(
      (l) => l["id"].toString() == entry["id"].toString(),
      orElse: () => entry,
    );

    final ai = _ai(liveLead);

    final phone = liveLead["phone"] ?? "";
    final createdAt = _parseDate(liveLead["created_at"]);
    final activities = liveLead["activities"] ?? [];
    final followDate = _parseDate(liveLead["follow_up_date"]);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: const Text("Details")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(child: _header(liveLead)),

          const SizedBox(height: 16),

          _card(
            color: Colors.deepPurple.withValues(alpha: 0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.auto_awesome, color: Colors.deepPurple),
                    SizedBox(width: 8),
                    Text(
                      "Smart Insight",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(ai["summary"]),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ai["actions"].map<Widget>((a) {
                    return InkWell(
                      onTap: () => _handleAction(
                        a["type"],
                        controller,
                        liveLead,
                        phone,
                        context,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(a["label"]),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section("Message", liveLead["msg"] ?? "-"),
                if (followDate != null)
                  _section("Follow-up", _formatDate(followDate)),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              _primaryButton(
                "WhatsApp",
                Icons.chat,
                const Color(0xFF25D366),
                () => _whatsapp(phone),
              ),
              const SizedBox(width: 10),
              _primaryButton(
                "Call",
                Icons.phone,
                Colors.deepPurple,
                () => _call(phone),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              _secondaryButton("Follow-up", Icons.schedule, () {
                controller.followUp(
                  liveLead,
                  "Follow-up",
                  DateTime.now().add(const Duration(days: 1)),
                );
              }),
              const SizedBox(width: 10),
              _secondaryButton(
                "Done",
                Icons.check,
                () => controller.markDone(liveLead),
              ),
            ],
          ),

          const SizedBox(height: 20),

          _card(
            child: _section(
              "Created",
              createdAt != null ? _formatDate(createdAt) : "-",
            ),
          ),

          const SizedBox(height: 20),

          const Text("Activity", style: TextStyle(fontWeight: FontWeight.w600)),

          const SizedBox(height: 10),

          ActivityTimeline(activities: activities),
        ],
      ),
    );
  }

  void _handleAction(
    String type,
    dynamic controller,
    Map<String, dynamic> lead,
    String phone,
    BuildContext context,
  ) {
    if (type == "call") {
      _call(phone);
    } else if (type == "whatsapp") {
      _whatsapp(phone);
    } else if (type == "done") {
      controller.markDone(lead);
    } else if (type == "follow") {
      controller.followUp(
        lead,
        "Follow-up",
        DateTime.now().add(const Duration(days: 1)),
      );
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(type.toUpperCase())));
  }

  Widget _card({required Widget child, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _header(Map<String, dynamic> lead) {
    final name = lead["name"] ?? "C";
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Colors.deepPurple.shade50,
          child: Text(name[0].toUpperCase()),
        ),
        const SizedBox(width: 10),
        Text(
          name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _section(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }

  Widget _primaryButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton(String label, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [Icon(icon), const SizedBox(height: 4), Text(label)],
          ),
        ),
      ),
    );
  }
}
