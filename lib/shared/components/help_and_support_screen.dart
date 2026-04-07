import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _contactSupport() async {
    final uri = Uri.parse(
      "mailto:closrsupport@gmail.com?subject=Closr Support",
    );
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Help & Support")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          /// 🔥 INTRO
          _card(
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Closr",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  "Manage leads, follow-ups, and orders from your chats — all in one place.",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// 🔥 QUICK HELP
          _section("Quick Help"),

          _card(
            child: const Column(
              children: [
                _HelpItem(
                  icon: Icons.add_circle_outline,
                  title: "Add a lead",
                  subtitle:
                      "Paste a WhatsApp message or speak using voice input",
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.psychology,
                  title: "AI understanding",
                  subtitle: "Closr detects intent and highlights hot customers",
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.track_changes,
                  title: "Follow-ups",
                  subtitle: "Get reminders so you never miss a potential deal",
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.check_circle_outline,
                  title: "Close orders",
                  subtitle: "Mark leads as completed once the deal is done",
                ),
                Divider(),
                _HelpItem(
                  icon: Icons.insights,
                  title: "Priority leads",
                  subtitle: "Focus on customers who are most likely to convert",
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// 🔥 SUPPORT
          _section("Support"),

          _card(
            child: ListTile(
              leading: const Icon(
                Icons.support_agent,
                color: Colors.deepPurple,
              ),
              title: const Text("Contact Support"),
              subtitle: const Text("Tap to email us"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: _contactSupport,
            ),
          ),

          const SizedBox(height: 20),

          /// 🔥 LEGAL
          _section("Legal"),

          _card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.privacy_tip,
                    color: Colors.deepPurple,
                  ),
                  title: const Text("Privacy Policy"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.description,
                    color: Colors.deepPurple,
                  ),
                  title: const Text("Terms of Service"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TermsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          /// 🔥 VERSION
          const Center(
            child: Text(
              "Closr • Version 1.0.0",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _HelpItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.deepPurple),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
