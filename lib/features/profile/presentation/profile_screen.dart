import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/shared/components/help_and-support_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/controller/auth_controller.dart';
import '../../auth/presentation/login_screen.dart';
import '../../notifications/presentation/notifications_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final supabase = Supabase.instance.client;

  final businessController = TextEditingController();
  final phoneController = TextEditingController();

  bool editingBusiness = false;
  bool editingPhone = false;

  User? get user => supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
  }

  /// 🔥 UPDATE FIELD
  Future<void> updateField(String key, String value) async {
    try {
      await supabase
          .from('users')
          .update({
            key: value,
            "updated_at": DateTime.now().toIso8601String(),
          })
          .eq('id', user!.id);

      if (mounted) setState(() {});

      ref.invalidate(userProfileProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Updated ✅")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error updating profile...")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final meta = authState.user?.userMetadata;

    
    final email = authState.user?.email ?? "";

    final profileAsync = ref.watch(userProfileProvider);

        final name = profileAsync.when(
      data: (data) => data?["business_name"] ?? "Your Business",
      loading: () => "Loading...",
      error: (_, __) => "Your Business",
    );

    final profile = profileAsync.value;


    businessController.text = profileAsync.value?["business_name"] ?? "";
    phoneController.text = profileAsync.value?["phone"] ?? "";

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),

      /// 🔥 FIXED LAYOUT
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(userProfileProvider);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  /// USER CARD
                  _card(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundImage: meta?["avatar_url"] != null
                              ? NetworkImage(meta!["avatar_url"])
                              : null,
                          child: meta?["avatar_url"] == null
                              ? const Icon(Icons.person, size: 30)
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(email,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// BUSINESS INLINE
                  _card(
                    child: Column(
                      children: [
                        _editableRow(
                          label: "Business Name",
                          value: profileAsync.value?["business_name"] ?? "",
                          controller: businessController,
                          isEditing: editingBusiness,
                          onEdit: () =>
                              setState(() => editingBusiness = true),
                          onSave: () async {
                            await updateField(
                                "business_name", businessController.text);
                            setState(() => editingBusiness = false);
                          },
                        ),
                        const Divider(height: 1),
                        _editableRow(
                          label: "Phone",
                          value: profileAsync.value?["phone"] ?? "",
                          controller: phoneController,
                          isEditing: editingPhone,
                          onEdit: () => setState(() => editingPhone = true),
                          onSave: () async {
                            final value = phoneController.text.trim();

                            final isValid = RegExp(r'^[0-9]{10}$').hasMatch(value);
                            if (!isValid) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Enter valid 10-digit phone number")),
                              );
                              return;
                            }

                            await updateField("phone", value);
                            setState(() => editingPhone = false);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// SETTINGS
                  _card(
                    child: Column(
                      children: [
                        _tile(
                          icon: Icons.notifications,
                          title: "Notifications",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        _tile(
                          icon: Icons.help_outline,
                          title: "Help & Support",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HelpSupportScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          /// 🔥 FULL WIDTH LOGOUT (FIXED)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await ref.read(authProvider.notifier).logout();

                  if (!mounted) return;

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: const Text(
                  "Logout",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🔥 EDITABLE ROW (FIXED VALUE SOURCE)
  Widget _editableRow({
    required String label,
    required String value,
    required TextEditingController controller,
    required bool isEditing,
    required VoidCallback onEdit,
    required VoidCallback onSave,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: isEditing
                ? TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: label == "Phone" ? TextInputType.phone : TextInputType.text,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: label == "Phone" ? "Enter valid phone number" : null,
                    ),
                    onChanged: (value) {
                      if (label == "Phone") {
                        final isValid = RegExp(r'^[0-9]{10}$').hasMatch(value);
                        if (!isValid && value.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Enter valid 10-digit phone number")),
                          );
                        }
                      }
                    },
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(value.isEmpty ? "Not set" : value),
                    ],
                  ),
          ),
          GestureDetector(
            onTap: isEditing ? onSave : onEdit,
            child: Icon(
              isEditing ? Icons.check : Icons.edit,
              size: 18,
              color: Colors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.deepPurple),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: onTap,
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}