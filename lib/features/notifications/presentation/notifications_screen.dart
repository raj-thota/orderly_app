import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/lead_navigation_service.dart';
import 'package:orderly_app/core/services/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsControllerProvider);

    final today = leads
        .where((lead) => NotificationService.isFollowUpToday(lead))
        .toList();

    final overdue = leads
        .where((lead) => NotificationService.isOverdueFollowUp(lead))
        .toList();

    final hasData = today.isNotEmpty || overdue.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          /// 🔥 CLEAR ALL (UI only for now)
          if (hasData)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Cleared (UI only)")),
                    );
                  },
                  child: const Text("Clear all"),
                ),
              ),
            ),

          /// 🔥 CONTENT
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: ListView(
                key: ValueKey(today.length + overdue.length),
                padding: const EdgeInsets.all(16),
                children: [
                  /// 🔥 URGENT
                  if (overdue.isNotEmpty) ...[
                    _title("🔥 Urgent"),
                    const SizedBox(height: 10),

                    ...overdue.map(
                      (lead) => _card(
                        context,
                        ref,
                        lead,
                        color: Colors.red,
                        label: "Missed follow-up",
                        action: "Call",
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],

                  /// 🟡 TODAY
                  if (today.isNotEmpty) ...[
                    _title("Today"),
                    const SizedBox(height: 10),

                    ...today.map(
                      (lead) => _card(
                        context,
                        ref,
                        lead,
                        color: Colors.orange,
                        label: "Follow-up today",
                        action: "Message",
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],

                  /// 🧠 AI
                  _title("AI Suggestions"),
                  const SizedBox(height: 10),

                  _aiCard(
                    context,
                    ref,
                    title: "🔥 Hot lead detected",
                    subtitle: "Customer asked price → send quote",
                  ),

                  _aiCard(
                    context,
                    ref,
                    title: "⏳ No response in 2h",
                    subtitle: "Send follow-up message",
                  ),

                  if (!hasData) _emptyState(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🔔 CARD (UPGRADED)
  Widget _card(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> lead, {
    required Color color,
    required String label,
    required String action,
  }) {
    final phone = lead["phone"] ?? "";
    final name = lead["name"] ?? "";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(
            context,
          ).push(LeadNavigationService.leadDetailRoute(lead));
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              /// ICON
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.notifications, color: color, size: 18),
              ),

              const SizedBox(width: 12),

              /// TEXT
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              /// ACTIONS
              Row(
                children: [
                  _actionBtn(color, action, () async {
                    try {
                      final url = action == "Call"
                          ? Uri.parse("tel:$phone")
                          : Uri.parse("https://wa.me/$phone");

                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (_) {}
                  }),

                  const SizedBox(width: 6),

                  _actionBtn(Colors.green, "Done", () {
                    ref.read(leadsControllerProvider.notifier).markDone(lead);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("$name marked done ✅")),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🧠 AI CARD
  Widget _aiCard(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.deepPurple),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),

          _actionBtn(Colors.deepPurple, "Act", () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("AI action coming soon 🤖")),
            );
          }),
        ],
      ),
    );
  }

  /// 🔘 PREMIUM BUTTON
  Widget _actionBtn(Color color, String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// TITLE
  Widget _title(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
  }

  /// EMPTY
  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.notifications_none, size: 50, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          const Text(
            "All caught up 🎉",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            "No pending follow-ups",
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
