import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/app/app_intro_screen.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/features/auth/controller/auth_controller.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/business/presentation/business_setup_screen.dart';
import 'package:orderly_app/main.dart';

enum RootDestination { loading, intro, setup, main }

/// Pure routing decision — unit tested.
RootDestination rootDestinationFor({
  required bool authed,
  required AsyncValue<BusinessProfile?> profile,
}) {
  if (!authed) return RootDestination.intro;
  return profile.when(
    data: (p) => p == null ? RootDestination.setup : RootDestination.main,
    loading: () => RootDestination.loading,
    error: (e, _) => RootDestination.main, // fail open into the app shell
  );
}

/// Watches auth + profile and renders the right root reactively. Logout flips
/// authProvider -> this rebuilds to the intro. Replaces imperative post-logout
/// navigation.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authProvider).isAuthenticated;
    final profile = ref.watch(businessProfileProvider);

    switch (rootDestinationFor(authed: authed, profile: profile)) {
      case RootDestination.intro:
        return const AppIntroScreen();
      case RootDestination.setup:
        return BusinessSetupScreen(
          onDone: () => ref.invalidate(businessProfileProvider),
        );
      case RootDestination.main:
        return const MainScreen();
      case RootDestination.loading:
        return const Scaffold(
          backgroundColor: AppColors.background,
          body: Center(child: CircularProgressIndicator()),
        );
    }
  }
}
