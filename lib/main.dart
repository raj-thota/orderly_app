import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:orderly_app/app/app_bootstrap.dart';
import 'package:orderly_app/app/app_setup_screen.dart';
import 'package:orderly_app/app/splash_screen.dart';
import 'package:orderly_app/core/theme/app_theme.dart';

// Core
import 'core/services/notification_service.dart';

// Features
import 'features/business/presentation/business_hub_screen.dart';
import 'features/today/presentation/today_screen.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/capture/presentation/capture_sheet.dart';
import 'features/orders/presentation/orders_screen.dart';
import 'features/orders/controller/orders_provider.dart';
import 'features/work/controller/work_items_provider.dart';
import 'features/work/presentation/my_work_screen.dart';

// Shared Widgets
import 'shared/widgets/app_bottom_nav.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Crash-reporting DSN, injected at build time via
/// `--dart-define=SENTRY_DSN=...`. Empty on local/dev builds, which run with
/// reporting disabled so nothing is required to boot the app.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrapState = await AppBootstrapper.bootstrap();

  void runner() =>
      runApp(ProviderScope(child: OrderlyApp(bootstrapState: bootstrapState)));

  if (_sentryDsn.isEmpty) {
    runner();
    return;
  }

  // SentryFlutter.init installs FlutterError + zone error handlers, so uncaught
  // widget and async errors are reported automatically.
  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    options.tracesSampleRate = 0.2;
    options.sendDefaultPii = false; // never ship user PII to the crash backend
  }, appRunner: runner);
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

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int currentIndex = 0;
  late final List<Widget> _screens;

  void changeTab(int index) {
    setState(() {
      currentIndex = index;
    });
    // Tabs live in an always-alive IndexedStack; refresh their data on entry
    // so captures, payments, and conversions made elsewhere show up.
    // 0=Today (shows orders+enquiries+work items), 1=My Work, 2=Orders.
    if (index == 0 || index == 2) {
      ref.read(ordersControllerProvider.notifier).load();
    }
    if (index == 0 || index == 1) {
      ref.read(enquiriesControllerProvider.notifier).load();
      ref.read(workItemsProvider.notifier).load();
    }
  }

  @override
  void initState() {
    super.initState();

    _screens = [
      TodayScreen(onNavigate: changeTab),
      const MyWorkScreen(),
      OrdersScreen(),
      const BusinessHubScreen(),
    ];

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.checkAndTriggerSmartReminders();
      NotificationService.consumePendingLaunchTap();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.checkAndTriggerSmartReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(index: currentIndex, children: _screens),
      bottomNavigationBar: AppBottomNav(
        currentIndex: currentIndex,
        onTap: changeTab,
        onFabTap: () => CaptureSheet.show(context),
      ),
    );
  }
}
