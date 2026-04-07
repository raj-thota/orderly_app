import 'package:flutter/material.dart';
import 'package:orderly_app/features/auth/presentation/login_screen.dart';

class AppIntroScreen extends StatefulWidget {
  const AppIntroScreen({super.key});

  @override
  State<AppIntroScreen> createState() => _AppIntroScreenState();
}

class _AppIntroScreenState extends State<AppIntroScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;

  int step = 0;
  bool showTyping = true;
  bool showMessage = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _runFlow();
  }

  void _runFlow() {
    Future.delayed(const Duration(milliseconds: 500), () {
      _runStep();
    });
  }

  void _runStep() async {
    if (!mounted) return;

    setState(() {
      step = 0;
      showTyping = true;
      showMessage = false;
    });

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() {
      showTyping = false;
      showMessage = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() => step = 1);

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() => step = 2);

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    _runStep();
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pulseController != null
        ? Tween<double>(begin: 0.95, end: 1.05).animate(_pulseController!)
        : const AlwaysStoppedAnimation(1.0);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),

              /// 🔥 BRAND (slightly polished)
              Column(
                children: [
                  Column(
                    children: [
                      /// LOGO
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Image.asset(
                          "assets/logo/logo.png",
                          height: 48,
                        ),
                      ),

                      const SizedBox(height: 16),

                      /// APP NAME
                      const Text(
                        "Closr",
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),

                      const SizedBox(height: 6),

                      /// TAGLINE
                      const Text(
                        "AI-powered follow-ups for your business",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 30),

              /// 🔥 FEATURES (UPGRADED ANIMATION)
              _feature(
                icon: Icons.notifications_active,
                title: "Smart Follow-ups",
                subtitle:
                    "Automatically reminds you to follow up with customers",
                delay: 0,
              ),
              const SizedBox(height: 16),
              _feature(
                icon: Icons.auto_graph,
                title: "Turn Chats into Orders",
                subtitle:
                    "Track leads, convert them into orders, and manage everything in one place",
                delay: 100,
              ),
              const SizedBox(height: 16),
              _feature(
                icon: Icons.psychology,
                title: "AI Powered Insights",
                subtitle:
                    "Identify hot customers and prioritize the ones ready to buy",
                delay: 200,
              ),

              const Spacer(),

              /// 🔥 LIVE DEMO (unchanged)
              _chatDemo(scale),

              const SizedBox(height: 20),

              /// 🔥 CTA
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Get Started",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                "Takes less than 30 seconds",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔥 CHAT DEMO (UNCHANGED)
  Widget _chatDemo(Animation<double> scale) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(radius: 14, child: Text("R")),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: showTyping
                      ? _typingDots()
                      : (showMessage
                            ? const Text(
                                "Hi, what's the price?",
                                style: TextStyle(fontSize: 13),
                              )
                            : const SizedBox()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _flowItem(Icons.chat, scale, active: true),
              _arrow(),
              _flowItem(Icons.person, scale, active: step >= 1),
              _arrow(),
              _flowItem(Icons.shopping_bag, scale, active: step >= 2),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Row(
              key: ValueKey(step),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (step == 0) ...[
                  const Icon(
                    Icons.smart_toy,
                    size: 14,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  step == 0
                      ? "AI is Analyzing conversation..."
                      : step == 1
                      ? "Lead created 🔥"
                      : "Order confirmed ✅",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 🔥 FEATURE (ANIMATED VERSION)
  Widget _feature({
    required IconData icon,
    required String title,
    required String subtitle,
    required int delay,
  }) {
    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 500 + delay),
      tween: Tween<double>(begin: 0, end: 1),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Row(
        children: [
          TweenAnimationBuilder(
            duration: const Duration(milliseconds: 600),
            tween: Tween<double>(begin: 0.8, end: 1),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.deepPurple, size: 20),
            ),
          ),
          const SizedBox(width: 12),
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
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Dot(),
        SizedBox(width: 4),
        Dot(delay: 200),
        SizedBox(width: 4),
        Dot(delay: 400),
      ],
    );
  }

  Widget _flowItem(
    IconData icon,
    Animation<double> scale, {
    required bool active,
  }) {
    return ScaleTransition(
      scale: scale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? Colors.deepPurple.withOpacity(0.15)
              : Colors.grey.shade300,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 14,
          color: active ? Colors.deepPurple : Colors.grey,
        ),
      ),
    );
  }

  Widget _arrow() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
    );
  }
}

/// 🔥 DOT (unchanged)
class Dot extends StatefulWidget {
  final int delay;
  const Dot({this.delay = 0, super.key});

  @override
  State<Dot> createState() => _DotState();
}

class _DotState extends State<Dot> with SingleTickerProviderStateMixin {
  late AnimationController controller;

  @override
  void initState() {
    super.initState();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: controller,
      child: const CircleAvatar(radius: 3, backgroundColor: Colors.grey),
    );
  }
}
