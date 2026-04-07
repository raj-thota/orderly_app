import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orderly_app/shared/widgets/stat_card.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/app_header.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final Function(int) onNavigate;

  const DashboardScreen({super.key, required this.onNavigate});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.read(leadsControllerProvider.notifier).loadLeads();
    });
  }

  List<Map<String, dynamic>> get leads => ref.watch(leadsControllerProvider);

  DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  int getLeadScore(Map<String, dynamic> lead) {
    int score = 0;

    final msg = (lead["msg"] ?? "").toString().toLowerCase();
    final intent = (lead["intent"] ?? "").toString();

    if (intent == "high") score += 50;
    if (msg.contains("price") || msg.contains("cost")) score += 20;
    if (msg.contains("buy") || msg.contains("order")) score += 30;

    final date = parseDate(lead["follow_up_date"]);
    if (lead["status"] == "follow" && date != null) {
      if (date.isBefore(DateTime.now())) score += 25;
    }

    final created = parseDate(lead["created_at"]);
    if (created != null && DateTime.now().difference(created).inHours < 2) {
      score += 15;
    }

    return score;
  }

  String getPriorityLabel(int score) {
    if (score > 70) return "🔥 Hot";
    if (score > 40) return "⚡ Warm";
    return "🧊 Cold";
  }

  String getSuggestion(Map<String, dynamic> lead) {
    final msg = (lead["msg"] ?? "").toString().toLowerCase();

    if (msg.contains("price")) return "Send price now";
    if (msg.contains("order")) return "Confirm order";
    return "Follow up now";
  }

  int getTodayFollowUps() {
    final today = DateTime.now();

    return leads.where((lead) {
      if (lead["status"] != "follow") return false;
      final date = parseDate(lead["follow_up_date"]);
      if (date == null) return false;

      return date.day == today.day &&
          date.month == today.month &&
          date.year == today.year;
    }).length;
  }

  int getOverdueFollowUps() {
    final now = DateTime.now();

    return leads.where((lead) {
      if (lead["status"] != "follow") return false;
      final date = parseDate(lead["follow_up_date"]);
      if (date == null) return false;

      return date.isBefore(now);
    }).length;
  }

  int getTotalLeads() => leads.length;
  int getFollowUps() => leads.where((l) => l["status"] == "follow").length;
  int getOrders() => leads.where((l) => l["status"] == "closed").length;

  int getCompletedToday() {
    final today = DateTime.now();

    return leads.where((lead) {
      if (lead["status"] != "closed") return false;
      final date = parseDate(lead["completed_at"]);
      if (date == null) return false;

      return date.day == today.day &&
          date.month == today.month &&
          date.year == today.year;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final followUpsToday = getTodayFollowUps();
    final overdue = getOverdueFollowUps();

    final actionLeads = leads.where((lead) {
      if (lead["status"] != "follow") return false;
      final date = parseDate(lead["follow_up_date"]);
      if (date == null) return false;
      return date.isBefore(DateTime.now());
    }).toList();

    final sortedLeads = [...leads];
    sortedLeads.sort((a, b) => getLeadScore(b).compareTo(getLeadScore(a)));

    final focusLeads = sortedLeads
        .where((l) => getLeadScore(l) > 40)
        .take(3)
        .toList();

    return SafeArea(
      child: Stack(
        children: [
          AppHeader(),

          Positioned.fill(
            top: MediaQuery.of(context).size.height * 0.22,
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(leadsControllerProvider);

                await ref.read(leadsControllerProvider.notifier).loadLeads();

                await Future.delayed(const Duration(milliseconds: 600));
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: ListView(
                  children: [
                    /// STATS
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: StatCard(
                                  "Leads",
                                  getTotalLeads().toString(),
                                  Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: StatCard(
                                  "Orders",
                                  getOrders().toString(),
                                  Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: StatCard(
                                  "Follow-ups",
                                  getFollowUps().toString(),
                                  Colors.red,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: StatCard(
                                  "Done",
                                  getCompletedToday().toString(),
                                  Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    /// PRIORITY LEADS
                    if (focusLeads.isNotEmpty) ...[
                      const Text(
                        "Priority Leads",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),

                      ...focusLeads.map((lead) {
                        final score = getLeadScore(lead);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.psychology,
                                color: Colors.deepPurple,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lead["name"] ?? "",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      getSuggestion(lead),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(getPriorityLabel(score)),
                            ],
                          ),
                        );
                      }),

                      const SizedBox(height: 20),
                    ],

                    /// FOLLOW-UP BANNER
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: overdue > 0
                            ? Colors.red.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications,
                            color: overdue > 0 ? Colors.red : Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              overdue > 0
                                  ? "$overdue leads need attention 🚨"
                                  : (followUpsToday == 0
                                        ? "You're all clear today 🎉"
                                        : "$followUpsToday follow-ups today"),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NotificationsScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              "View",
                              style: TextStyle(color: Colors.deepPurple),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// ACTION REQUIRED
                    const Text(
                      "Action Required",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    ...actionLeads.map((lead) {
                      final score = getLeadScore(lead);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red.shade200),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lead["name"] ?? "",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "💡 ${getSuggestion(lead)}",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    getPriorityLabel(score),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),

                            Row(
                              children: [
                                _circleBtn(Icons.check, Colors.green, () async {
                                  await ref
                                      .read(leadsControllerProvider.notifier)
                                      .markDone(lead);
                                }),
                                const SizedBox(width: 8),
                                _circleBtn(
                                  FontAwesomeIcons.whatsapp,
                                  const Color(0xFF25D366),
                                  () async {
                                    final phone = lead["phone"] ?? "";
                                    final url = Uri.parse(
                                      "https://wa.me/$phone",
                                    );
                                    await launchUrl(
                                      url,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                _circleBtn(
                                  FontAwesomeIcons.phone,
                                  Colors.deepPurple,
                                  () async {
                                    final phone = lead["phone"] ?? "";
                                    await launchUrl(Uri.parse("tel:$phone"));
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                    if (actionLeads.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "You're all caught up 🎉",
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap) {
    return Container(
      height: 36,
      width: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: Colors.white, size: 16),
        onPressed: onTap,
      ),
    );
  }
}
