import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:orderly_app/shared/components/add_entry_selector.dart';
import 'package:orderly_app/app/splash_screen.dart';

// Core
import 'core/services/notification_service.dart';

// Features
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/leads/presentation/leads_screen.dart';
import 'features/orders/presentation/orders_screen.dart';

// Shared Widgets
import 'shared/widgets/app_bottom_nav.dart';

import 'package:app_links/app_links.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// 🔐 LOAD ENV
  await dotenv.load(fileName: ".env");

  final appLinks = AppLinks();

appLinks.uriLinkStream.listen((uri) async {
  print("DEEP LINK RECEIVED: $uri");

  final res = await Supabase.instance.client.auth.getSessionFromUrl(uri);

  print("SESSION FROM URL: ${res.session}");
});

  /// 🔥 SUPABASE INIT
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  await NotificationService.init();

  runApp(const ProviderScope(child: OrderlyApp()));
}

class OrderlyApp extends ConsumerWidget {
  const OrderlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "Closr",
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SplashScreen(),
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

  void changeTab(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();

    /// ⚠️ Remove later (debug only)
    Future.delayed(const Duration(seconds: 5), () {
      NotificationService.showNotification(
        title: "Test Notification",
        body: "If you see this → working 🎉",
      );
    });

    Future.delayed(const Duration(seconds: 2), () {
      NotificationService.checkAndTriggerSmartReminders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(onNavigate: changeTab),
      const LeadsScreen(),
      OrdersScreen(),
    ];

    return Scaffold(
      body: screens[currentIndex],

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurple,
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => AddEntrySelector(),
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
