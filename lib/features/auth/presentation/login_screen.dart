import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../controller/auth_controller.dart';
import '../../../main.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);

    ref.listen(authProvider, (previous, next) {
      if (next.isAuthenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        });
      }

      final previousError = previous?.errorMessage;
      final nextError = next.errorMessage;

      if (nextError != null && nextError != previousError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(nextError)));
          ref.read(authProvider.notifier).clearError();
        });
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            offset: const Offset(0, 0.05),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  /// 🔥 BRAND
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Color(0xFFF3EFFF),
                          child: Image.asset(
                            "assets/logo/logo.png",
                            height: 90,
                          ),
                        ),
                        SizedBox(height: 14),
                        Text(
                          "Welcome to Closr",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "AI-powered follow-ups for your business",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  /// 🔥 VALUE LINE
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 20,
                          color: Colors.deepPurple,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Turn chats → leads → orders",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  /// 🔥 BENEFITS
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _BenefitItem(
                        text: "Never miss a follow-up again",
                        index: 0,
                      ),
                      SizedBox(height: 10),
                      _BenefitItem(
                        text: "Track leads & orders in one place",
                        index: 1,
                      ),
                      SizedBox(height: 10),
                      _BenefitItem(
                        text: "AI tells you who is ready to buy",
                        index: 2,
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  /// 🔥 GOOGLE LOGIN BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 120),
                      scale: state.isLoading ? 0.98 : 1,
                      child: ElevatedButton(
                        onPressed: state.isLoading
                            ? null
                            : () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Redirecting to Google..."),
                                  ),
                                );

                                await ref
                                    .read(authProvider.notifier)
                                    .loginWithGoogle();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C4ED9),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          child: state.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const FaIcon(
                                        FontAwesomeIcons.google,
                                        size: 16,
                                        color: Color(0xFFDB4437),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      "Continue with Google",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Center(
                    child: Text(
                      "One tap login • No password needed",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// 🔥 TRUST BADGES
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: const [
                      Column(
                        children: [
                          Icon(Icons.lock, size: 18, color: Colors.grey),
                          SizedBox(height: 4),
                          Text(
                            "Secure",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(Icons.flash_on, size: 18, color: Colors.grey),
                          SizedBox(height: 4),
                          Text(
                            "Fast Setup",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(Icons.cloud_done, size: 18, color: Colors.grey),
                          SizedBox(height: 4),
                          Text(
                            "Synced",
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  const Center(
                    child: Text(
                      "Built for small businesses & founders",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitItem extends StatefulWidget {
  final String text;
  final int index;
  const _BenefitItem({required this.text, this.index = 0});

  @override
  State<_BenefitItem> createState() => _BenefitItemState();
}

class _BenefitItemState extends State<_BenefitItem>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late Animation<double> fade;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    Future.delayed(Duration(milliseconds: 120 * widget.index), () {
      if (mounted) controller.forward();
    });

    fade = CurvedAnimation(parent: controller, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Text(widget.text, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
