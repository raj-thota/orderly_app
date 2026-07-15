import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:orderly_app/app/app_bootstrap.dart';
import 'package:orderly_app/app/app_setup_screen.dart';
import 'package:orderly_app/app/splash_screen.dart';
import 'package:orderly_app/core/theme/app_theme.dart';

// Core
import 'core/services/notification_service.dart';

// Features
import 'package:orderly_app/core/theme/app_colors.dart';

import 'features/business/presentation/business_hub_screen.dart';
import 'features/leads/controller/leads_controller.dart';
import 'features/today/presentation/today_screen.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/capture/presentation/capture_sheet.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiries_screen.dart';
import 'features/orders/presentation/orders_screen.dart';
import 'features/orders/controller/orders_provider.dart';

// Shared Widgets
import 'shared/widgets/app_bottom_nav.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrapState = await AppBootstrapper.bootstrap();

  runApp(ProviderScope(child: OrderlyApp(bootstrapState: bootstrapState)));
}

class OrderlyApp extends StatelessWidget {
  final AppBootstrapState bootstrapState;

  const OrderlyApp({
    super.key,
    this.bootstrapState = const AppBootstrapState.missingConfiguration(),
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: "Closr",
      theme: AppTheme.light,
      home: bootstrapState.isReady
          ? const SplashScreen()
          : AppSetupScreen(message: bootstrapState.message),
    );
  }
}

/// 🏠 Main App Screen
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int currentIndex = 0;
  late final List<Widget> _screens;

  void changeTab(int index) {
    setState(() {
      currentIndex = index;
    });
    // Tabs live in an always-alive IndexedStack; refresh their data on entry
    // so captures, payments, and conversions made elsewhere show up.
    // 0=Today (shows orders+enquiries), 1=My Work, 2=Orders, 3=Business.
    if (index == 0 || index == 2) {
      ref.read(ordersControllerProvider.notifier).load();
    }
    if (index == 0 || index == 1) {
      ref.read(enquiriesControllerProvider.notifier).load();
    }
  }

  @override
  void initState() {
    super.initState();

    _screens = [
      TodayScreen(onNavigate: changeTab),
      const EnquiriesScreen(), // temporary My Work host; replaced in M4
      OrdersScreen(),
      const BusinessHubScreen(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.checkAndTriggerSmartReminders();
      // Orders load once at cold open via OrdersScreen.initState (all
      // IndexedStack children build on first paint) — no prime needed here.
      // Dashboard used to trigger the legacy load that syncs follow-up
      // notifications; owned here until M4 rebuilds the engine.
      // TODO(M4): remove; SplashScreen already primes this on login.
      ref.read(leadsControllerProvider.notifier).loadLeads();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: currentIndex, children: _screens),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        onPressed: () => CaptureSheet.show(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: currentIndex,
        onTap: changeTab,
      ),
    );
  }
}
