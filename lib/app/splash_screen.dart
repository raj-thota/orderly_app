import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/app/app_intro_screen.dart';
import 'package:orderly_app/core/services/auth_service.dart';
import 'package:orderly_app/features/leads/controller/leads_controller.dart';
import 'package:orderly_app/features/auth/controller/auth_controller.dart';
import 'package:orderly_app/main.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  String loadingText = "Initializing...";

  @override
  void initState() {
    super.initState();

    /// 🔥 Animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    /// 🔥 Start app init
    Future.microtask(() => _initApp());
  }

  void _setLoadingText(String value) {
    if (!mounted) return;
    setState(() => loadingText = value);
  }

  Future<void> _initApp() async {
    final authController = ref.read(authProvider.notifier);

    _setLoadingText("Checking session...");

    await authController.checkAuth();

    final isLoggedIn = ref.read(authProvider).isAuthenticated;

    if (isLoggedIn) {
      _setLoadingText("Setting up your workspace...");
      await AuthService().ensureUserProfile();

      _setLoadingText("Loading your leads...");
      await ref.read(leadsControllerProvider.notifier).loadLeads();
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            isLoggedIn ? const MainScreen() : const AppIntroScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        color: const Color(0xFF0B0F2A),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Image.asset("assets/logo/logo.png", height: 90),
              ),
              const SizedBox(height: 24),
              const Text(
                "Closr",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Close deals from chats, instantly",
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 30),
              Text(
                loadingText,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
