import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orderly_app/core/services/leads_service.dart';
import 'package:orderly_app/core/utils/message_parser.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:orderly_app/shared/widgets/activity_timeline.dart';
import 'package:url_launcher/url_launcher.dart';

final leadDetailProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, leadId) async {
    return LeadsService().fetchLeadById(leadId);
  },
);

class EntryDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> entry;

  const EntryDetailScreen({super.key, required this.entry});

  Future<void> _call(String phone) async {
    final url = Uri.parse("tel:$phone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _whatsapp(String phone) async {
    final url = Uri.parse("https://wa.me/$phone");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDate(DateTime d) => "${d.day}/${d.month}/${d.year}";

  String _formatShortDate(DateTime d) {
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
    return "${d.day} ${months[d.month - 1]}";
  }

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
      summary = "Customer looks ready to place the order.";
      actions = [
        {"label": "Confirm", "type": "done"},
        {"label": "WhatsApp", "type": "whatsapp"},
      ];
    } else if (intent == "follow_up") {
      summary = "Lead needs a quick follow-up to keep momentum going.";
      actions = [
        {"label": "Follow-up", "type": "follow"},
        {"label": "Call", "type": "call"},
      ];
    } else {
      summary = "Fresh inquiry. Best next move is quick engagement.";
      actions = [
        {"label": "WhatsApp", "type": "whatsapp"},
        {"label": "Call", "type": "call"},
      ];
    }

    if (items.isNotEmpty) {
      actions.add({"label": "Items", "type": "follow"});
    }

    return {"summary": summary, "actions": actions};
  }

  String _statusLabel(Map<String, dynamic> lead) {
    switch ((lead["status"] ?? "").toString().toLowerCase()) {
      case "follow":
        return "Follow-up";
      case "closed":
        return "Order";
      case "new":
        return "New";
      default:
        return "Open";
    }
  }

  Color _statusColor(Map<String, dynamic> lead) {
    switch ((lead["status"] ?? "").toString().toLowerCase()) {
      case "follow":
        return const Color(0xFFE08B00);
      case "closed":
        return const Color(0xFF0F9D58);
      case "new":
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsControllerProvider);
    final controller = ref.read(leadsControllerProvider.notifier);
    final leadId = entry["id"]?.toString();

    final cachedLead = leadId == null ? null : _findLeadById(leads, leadId);

    if (cachedLead != null) {
      return _buildScreen(context, controller, cachedLead);
    }

    if (leadId == null) {
      return _buildScreen(context, controller, entry);
    }

    final liveLeadAsync = ref.watch(leadDetailProvider(leadId));

    return liveLeadAsync.when(
      data: (liveLead) {
        if (liveLead == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Lead Detail")),
            body: const Center(child: Text("Lead not found")),
          );
        }

        return _buildScreen(context, controller, liveLead);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text("Lead Detail")),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text("Lead Detail")),
        body: const Center(child: Text("Could not load lead")),
      ),
    );
  }

  Map<String, dynamic>? _findLeadById(
    List<Map<String, dynamic>> leads,
    String leadId,
  ) {
    for (final lead in leads) {
      if (lead["id"]?.toString() == leadId) {
        return lead;
      }
    }
    return null;
  }

  Widget _buildScreen(
    BuildContext context,
    dynamic controller,
    Map<String, dynamic> liveLead,
  ) {
    final ai = _ai(liveLead);
    final phone = (liveLead["phone"] ?? "").toString();
    final name = (liveLead["name"] ?? "Lead").toString();
    final message = (liveLead["msg"] ?? "-").toString();
    final createdAt = _parseDate(liveLead["created_at"]);
    final activities = liveLead["activities"] ?? [];
    final followDate = _parseDate(liveLead["follow_up_date"]);
    final items = (liveLead["items"] ?? []) as List;
    final statusLabel = _statusLabel(liveLead);
    final statusColor = _statusColor(liveLead);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text("Lead Detail"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(liveLead),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(statusLabel, statusColor),
                    if (followDate != null)
                      _pill(
                        "Follow-up ${_formatShortDate(followDate)}",
                        const Color(0xFF6C4ED9),
                      ),
                    if (phone.trim().isNotEmpty)
                      _pill("Phone linked", const Color(0xFF0F9D58)),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  ai["summary"],
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF374151),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            color: const Color(0xFFF8F5FF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: Color(0xFF6C4ED9)),
                    SizedBox(width: 8),
                    Text(
                      "Smart Insight",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  ai["summary"],
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF374151),
                  ),
                ),
                // const SizedBox(height: 12),
                // Wrap(
                //   spacing: 8,
                //   runSpacing: 8,
                //   children: ai["actions"].map<Widget>((a) {
                //     return _compactButton(
                //       label: a["label"],
                //       icon: _actionIcon(a["type"]),
                //       color: const Color(0xFF6C4ED9),
                //       onTap: () => _handleAction(
                //         a["type"],
                //         controller,
                //         liveLead,
                //         phone,
                //         context,
                //       ),
                //     );
                //   }).toList(),
                // ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section(
                  "Message Preview",
                  message,
                  icon: Icons.chat_bubble_outline_rounded,
                ),
                if (followDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _section(
                      "Follow-up Date",
                      _formatDate(followDate),
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                if (phone.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _section("Phone", phone, icon: Icons.phone_outlined),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _smallActionButton(
                "WhatsApp",
                FontAwesomeIcons.whatsapp,
                const Color(0xFF25D366),
                () => _whatsapp(phone),
              ),
              const SizedBox(width: 10),
              _smallActionButton(
                "Call",
                FontAwesomeIcons.phone,
                const Color(0xFF6C4ED9),
                () => _call(phone),
              ),
              const SizedBox(width: 10),
              _smallActionButton(
                "Convert to order",
                FontAwesomeIcons.cartShopping,
                const Color(0xFF0F9D58),
                () => controller.markDone(liveLead),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _compactButton(
                label: "Schedule follow-up",
                icon: FontAwesomeIcons.clockRotateLeft,
                color: const Color(0xFFE08B00),
                onTap: () {
                  controller.followUp(
                    liveLead,
                    "Follow-up",
                    DateTime.now().add(const Duration(days: 1)),
                  );
                },
              ),
              if (items.isNotEmpty)
                _compactButton(
                  label: "${items.length} items",
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFF0F9D58),
                  onTap: () {},
                ),
            ],
          ),
          const SizedBox(height: 20),
          _card(
            child: Row(
              children: [
                Expanded(
                  child: _statTile(
                    "Created",
                    createdAt != null ? _formatShortDate(createdAt) : "-",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statTile("Status", statusLabel, color: statusColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Activity",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
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

  Widget _heroCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF6F2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7DDFE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C4ED9).withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _card({required Widget child, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _header(Map<String, dynamic> lead) {
    final name = (lead["name"] ?? "C").toString();
    final phone = (lead["phone"] ?? "").toString();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFEEE7FF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: Text(
              name[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6C4ED9),
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
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                phone.isEmpty ? "No phone added" : phone,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title, String value, {required IconData icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Color(0xFF111827),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _pill(String label, Color color, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? color : color.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }

  IconData _actionIcon(String type) {
    switch (type) {
      case "call":
        return Icons.call_rounded;
      case "whatsapp":
        return Icons.chat_bubble_rounded;
      case "done":
        return Icons.check_circle_rounded;
      case "follow":
        return Icons.schedule_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  Widget _smallActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 35,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              color: color ?? const Color(0xFF111827),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
