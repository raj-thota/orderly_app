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

import 'features/catalog/presentation/catalog_screen.dart';
import 'features/catalog/presentation/product_form_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiries_screen.dart';
import 'package:orderly_app/features/enquiries/presentation/capture_screen.dart';
import 'features/orders/presentation/orders_screen.dart';

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
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int currentIndex = 0;
  late final List<Widget> _screens;

  void changeTab(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();

    _screens = [
      DashboardScreen(onNavigate: changeTab),
      const EnquiriesScreen(),
      OrdersScreen(),
      const CatalogScreen(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.checkAndTriggerSmartReminders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: currentIndex, children: _screens),

      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {
          if (currentIndex == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductFormScreen()),
            );
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CaptureScreen()),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),

      bottomNavigationBar: AppBottomNav(
        currentIndex: currentIndex,
        onTap: changeTab,
      ),
    );
  }
}
