import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:orderly_app/shared/components/help_and_support_screen.dart';

/// One-line status shown under the business name on the dashboard. Pure so it
/// can be unit-tested. Counts open follow-ups due today or overdue, plus fresh
/// enquiries still to chase; falls back to an all-clear message.
String dashboardDailyBrief(List<Map<String, dynamic>> leads, DateTime now) {
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
  var followUpsDue = 0;
  var toChase = 0;
  for (final l in leads) {
    final status = l['status']?.toString();
    if (status == 'closed' || status == 'won' || status == 'lost') continue;
    final d = DateTime.tryParse(l['follow_up_date']?.toString() ?? '');
    if (d != null && !d.isAfter(endOfToday)) followUpsDue++;
    if (status == 'new') toChase++;
  }
  final parts = <String>[];
  if (followUpsDue > 0) {
    parts.add('$followUpsDue follow-up${followUpsDue == 1 ? '' : 's'} due');
  }
  if (toChase > 0) {
    parts.add('$toChase ${toChase == 1 ? 'enquiry' : 'enquiries'} to chase');
  }
  if (parts.isEmpty) return "You're all caught up today 🎉";
  return parts.join(' · ');
}

class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.value;

    final name = profile?["business_name"] ?? "Your Business";
    final avatar = profile?["avatar_url"];

    final leads = ref.watch(leadsControllerProvider);
    final now = DateTime.now();

    final notifCount = leads.where((l) {
      final d = DateTime.tryParse(l["follow_up_date"]?.toString() ?? "");
      return d != null && d.isBefore(now) && l["status"] != "closed";
    }).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF5B0EAF), Color(0xFF7B2FF7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 🔥 TOP ROW
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              /// 👤 PROFILE
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                child: Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: avatar != null && avatar.toString().isNotEmpty
                        ? Image.network(avatar, fit: BoxFit.cover)
                        : const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),

              Row(
                children: [
                  /// 🔔 NOTIFICATIONS
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationsScreen(),
                            ),
                          );
                        },
                        child: _squareIcon(icon: Icons.notifications_none),
                      ),

                      if (notifCount > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              notifCount > 9 ? "9+" : notifCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 10),

                  /// ❓ HELP
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HelpSupportScreen(),
                        ),
                      );
                    },
                    child: _squareIcon(icon: Icons.help_outline),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 22),

          const Text(
            "Welcome back,",
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),

          const SizedBox(height: 4),

          Text(
            "$name 👋",
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            dashboardDailyBrief(leads, now),
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _squareIcon({required IconData icon}) {
    return Container(
      height: 42,
      width: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}
