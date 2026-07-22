import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../controller/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _googleLoading = false;
  bool _appleLoading = false;
  StreamSubscription<supa.AuthState>? _authSub;

  bool get _busy => _googleLoading || _appleLoading;

  // Sign in with Apple is required by App Store Guideline 4.8 wherever a
  // third-party social login (Google) is offered, and the native flow only
  // exists on Apple platforms — so the button is iOS-only.
  bool get _showApple => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Google is a redirect (browser) flow: launch it, then wait for the deep
  /// link callback to deliver a session before navigating.
  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _googleLoading = true);
    try {
      await ref.read(authProvider.notifier).loginWithGoogle();
      _authSub?.cancel();
      _authSub = supa.Supabase.instance.client.auth.onAuthStateChange.listen((
        data,
      ) {
        if (data.session != null && mounted) {
          _authSub?.cancel();
          // Pop to RootGate (app root); it routes new users to business
          // setup and returning users to the main shell.
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Google sign-in failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Google sign-in didn't work. Please try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  /// Apple is a native flow: it returns a session in one call, so we can
  /// navigate as soon as it succeeds.
  Future<void> _signInWithApple() async {
    if (_busy) return;
    setState(() => _appleLoading = true);
    try {
      final ok = await ref.read(authProvider.notifier).loginWithApple();
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Apple sign-in didn't work. Please try again."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Image.asset('assets/logo/logo.png', height: 48),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Welcome to Closr',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Your AI-powered sales assistant',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Text(
                'Sign in to continue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Apple first on iOS per Apple's HIG.
              if (_showApple) ...[
                _AppleButton(
                  loading: _appleLoading,
                  onPressed: _busy ? null : _signInWithApple,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _GoogleButton(
                loading: _googleLoading,
                onPressed: _busy ? null : _signInWithGoogle,
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'By continuing you agree to our Terms of Service',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.onPressed});
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        key: const Key('google_signin_btn'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'G',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.loading, required this.onPressed});
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        key: const Key('apple_signin_btn'),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          disabledBackgroundColor: Colors.black45,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FaIcon(FontAwesomeIcons.apple, color: Colors.white, size: 18),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    'Continue with Apple',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
