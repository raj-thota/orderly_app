# M0 — Nav Restructure + Today Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the app to the V1.0.0 shell — Today · My Work · [+] · Orders · Business bottom nav, a real DB-backed Today brief, a Business hub, mock-aligned palette — and delete the legacy Dashboard.

**Architecture:** Pure-function brief (`buildTodayBrief`) computed from the already-loaded orders + enquiries providers (no new service, no AI). New `features/today` and a `BusinessHubScreen`; My Work tab temporarily hosts the existing `EnquiriesScreen` (replaced in M4). Legacy `DashboardScreen`/`AppHeader`/`StatCard` deleted; `leadsControllerProvider` survives until M4 because `NotificationsScreen` and notification sync still depend on it.

**Tech Stack:** Flutter, Riverpod 2 (StateNotifier pattern), existing `Money`/`EventService`/`Enquiry`/`Order` models. No new packages, no DB changes.

**TDD source:** `docs/superpowers/specs/2026-07-11-closr-v1.0.0-tdd.md` (§0a fidelity mandate, §3, §4, §14 M0 row).

**Verify commands:** `flutter analyze` and `flutter test` (both must be clean at every commit).

---

### Task 1: Mock palette tokens

The mock's primary is an indigo-violet, not the current plum. Values below are read from the V1.0.0 mock; **flag to Raj for confirmation against the Figma source before this commit** (fidelity mandate §0a) — if he supplies different hex, substitute 1:1, everything else in this plan reads tokens only.

**Files:**
- Modify: `lib/core/theme/app_colors.dart`

- [ ] **Step 1: Update the color tokens**

Replace the Brand block and add AI tokens in `lib/core/theme/app_colors.dart`:

```dart
  // Brand — V1 indigo (per V1.0.0 mock; confirm exact hex against Figma)
  static const Color primary = Color(0xFF5B4FE9);
  static const Color primaryDark = Color(0xFF4638C9);
  static const Color accent = Color(0xFFE0A82E); // warm gold (legacy, unused in V1 mock)

  // AI surfaces (lilac cards: summary, suggested reply, brief chips)
  static const Color aiSurface = Color(0xFFF1EFFE);
  static const Color aiAccent = Color(0xFF7A6CF0);

  // Today brief card gradient
  static const Color briefGradientStart = Color(0xFF7C6BF7);
  static const Color briefGradientEnd = Color(0xFF5B4FE9);
```

Keep every other token unchanged.

- [ ] **Step 2: Verify nothing broke**

Run: `flutter analyze && flutter test`
Expected: no issues, all tests pass (tokens are referenced by name only).

- [ ] **Step 3: Commit**

```bash
git add lib/core/theme/app_colors.dart
git commit -m "feat(theme): align palette to V1 mock, add AI surface tokens"
```

---

### Task 2: `buildTodayBrief` pure function

DB-only brief numbers (TDD M0: outstanding ₹, due follow-ups, orders — no AI). Pure so it unit-tests without Supabase, mirroring `dashboardDailyBrief`'s testability (which this replaces).

**Files:**
- Create: `lib/features/today/data/today_brief.dart`
- Test: `test/features/today/today_brief_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/payments/data/payment.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';

void main() {
  final now = DateTime(2026, 7, 11, 10); // Saturday 10:00

  group('buildTodayBrief', () {
    test('zeroes on empty data', () {
      final b = buildTodayBrief(orders: [], enquiries: [], now: now);
      expect(b.outstanding, 0);
      expect(b.dueFollowUps, 0);
      expect(b.ordersToday, 0);
      expect(b.revenueToday, 0);
    });

    test('outstanding sums dues across all orders', () {
      final orders = [
        Order(grandTotal: 1000, payments: [Payment(amount: 400)]), // 600 due
        const Order(grandTotal: 500), // 500 due
        Order(grandTotal: 300, payments: [Payment(amount: 300)]), // paid
      ];
      final b = buildTodayBrief(orders: orders, enquiries: [], now: now);
      expect(b.outstanding, 1100);
    });

    test('dueFollowUps counts overdue and today buckets only', () {
      final enquiries = [
        Enquiry(status: 'follow', followUpDate: DateTime(2026, 7, 10)), // overdue
        Enquiry(status: 'follow', followUpDate: DateTime(2026, 7, 11, 18)), // today
        Enquiry(status: 'follow', followUpDate: DateTime(2026, 7, 20)), // upcoming
        const Enquiry(status: 'new'), // fresh
      ];
      final b = buildTodayBrief(orders: [], enquiries: enquiries, now: now);
      expect(b.dueFollowUps, 2);
    });

    test('ordersToday counts orders created today only', () {
      final orders = [
        Order(createdAt: DateTime(2026, 7, 11, 1)),
        Order(createdAt: DateTime(2026, 7, 11, 23)),
        Order(createdAt: DateTime(2026, 7, 10, 23)),
        const Order(), // null createdAt
      ];
      final b = buildTodayBrief(orders: orders, enquiries: [], now: now);
      expect(b.ordersToday, 2);
    });

    test('revenueToday sums payments received today across orders', () {
      final orders = [
        Order(grandTotal: 5000, payments: [
          Payment(amount: 2000, paidAt: DateTime(2026, 7, 11, 9)),
          Payment(amount: 1000, paidAt: DateTime(2026, 7, 10, 9)), // yesterday
        ]),
        Order(grandTotal: 800, payments: [
          Payment(amount: 800, paidAt: DateTime(2026, 7, 11, 8)),
        ]),
      ];
      final b = buildTodayBrief(orders: orders, enquiries: [], now: now);
      expect(b.revenueToday, 2800);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/today/today_brief_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package ... today_brief.dart` (file does not exist).

- [ ] **Step 3: Write the implementation**

`lib/features/today/data/today_brief.dart`:

```dart
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/orders/data/order.dart';

/// DB-only numbers for the Today brief card (M0: no AI involved).
/// Pure so it can be unit-tested without Supabase.
class TodayBrief {
  const TodayBrief({
    this.outstanding = 0,
    this.dueFollowUps = 0,
    this.ordersToday = 0,
    this.revenueToday = 0,
  });

  final double outstanding;
  final int dueFollowUps;
  final int ordersToday;
  final double revenueToday;
}

TodayBrief buildTodayBrief({
  required List<Order> orders,
  required List<Enquiry> enquiries,
  required DateTime now,
}) {
  bool sameDay(DateTime? d) =>
      d != null && d.year == now.year && d.month == now.month && d.day == now.day;

  var outstanding = 0.0;
  var ordersToday = 0;
  var revenueToday = 0.0;
  for (final o in orders) {
    outstanding += o.dues;
    if (sameDay(o.createdAt)) ordersToday++;
    for (final p in o.payments) {
      if (sameDay(p.paidAt)) revenueToday += p.amount;
    }
  }

  final dueFollowUps = enquiries.where((e) {
    final bucket = e.bucket(now);
    return bucket == EnquiryBucket.overdue || bucket == EnquiryBucket.today;
  }).length;

  return TodayBrief(
    outstanding: outstanding,
    dueFollowUps: dueFollowUps,
    ordersToday: ordersToday,
    revenueToday: revenueToday,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/today/today_brief_test.dart`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/today/data/today_brief.dart test/features/today/today_brief_test.dart
git commit -m "feat(today): pure DB-only brief calculator"
```

---

### Task 3: TodayScreen

Mock layout, v0 content: header (greeting + bell), gradient brief card with the four numbers + "Start My Work →" button, and a due-follow-ups nudge row that jumps to the My Work tab. Approval queue and AI copy arrive in M4 — do not fake them (TDD honesty rule).

**Files:**
- Create: `lib/features/today/presentation/today_screen.dart`
- Test: `test/features/today/today_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';
import 'package:orderly_app/features/payments/data/payment.dart';
import 'package:orderly_app/features/today/presentation/today_screen.dart';

class _FixedOrders extends OrdersController {
  _FixedOrders(List<Order> orders) : super(OrdersService()) {
    state = AsyncValue.data(orders);
  }
  @override
  Future<void> load() async {}
}

class _FixedEnquiries extends EnquiriesController {
  _FixedEnquiries(List<Enquiry> enquiries) : super(EnquiriesService()) {
    state = AsyncValue.data(enquiries);
  }
  @override
  Future<void> load() async {}
}

void main() {
  Widget harness({
    required List<Order> orders,
    required List<Enquiry> enquiries,
    required List<String> events,
    void Function(int)? onNavigate,
  }) {
    return ProviderScope(
      overrides: [
        ordersControllerProvider.overrideWith((ref) => _FixedOrders(orders)),
        enquiriesControllerProvider
            .overrideWith((ref) => _FixedEnquiries(enquiries)),
        userProfileProvider
            .overrideWith((ref) async => {'business_name': 'Raj'}),
        eventServiceProvider.overrideWithValue(EventService(
          sink: (row) async => events.add(row['name'] as String),
          currentUserId: () => 'u1',
        )),
      ],
      child: MaterialApp(
        home: TodayScreen(onNavigate: onNavigate ?? (_) {}),
      ),
    );
  }

  final dueEnquiry = Enquiry(
    status: 'follow',
    followUpDate: DateTime.now().subtract(const Duration(days: 1)),
    customerName: 'Meena',
  );

  testWidgets('renders brief numbers from orders and enquiries',
      (tester) async {
    final orders = [
      Order(grandTotal: 9500, payments: [
        Payment(amount: 9500, paidAt: DateTime.now()),
      ], createdAt: DateTime.now()),
      const Order(grandTotal: 12000), // outstanding
    ];
    await tester.pumpWidget(harness(
        orders: orders, enquiries: [dueEnquiry], events: []));
    await tester.pumpAndSettle();

    expect(find.text('₹12,000'), findsOneWidget); // outstanding
    expect(find.text('₹9,500'), findsOneWidget); // revenue today
    expect(find.textContaining('Raj'), findsOneWidget); // greeting
    expect(find.text('Start My Work'), findsOneWidget);
  });

  testWidgets('Start My Work navigates to tab 1', (tester) async {
    int? navigated;
    await tester.pumpWidget(harness(
        orders: [], enquiries: [], events: [], onNavigate: (i) => navigated = i));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start My Work'));
    expect(navigated, 1);
  });

  testWidgets('tracks brief_view once on open', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(harness(orders: [], enquiries: [], events: events));
    await tester.pumpAndSettle();
    expect(events, ['brief_view']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/today/today_screen_test.dart`
Expected: FAIL — `today_screen.dart` does not exist.

- [ ] **Step 3: Implement TodayScreen**

`lib/features/today/presentation/today_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/notifications/presentation/notifications_screen.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';

/// Home tab per the V1 mock: greeting, brief card, due-work nudge.
/// M0 = DB-only numbers; AI brief copy and approval queue land in M4.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, required this.onNavigate});

  final void Function(int tab) onNavigate;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(eventServiceProvider).track('brief_view');
    });
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersControllerProvider).valueOrNull ?? const [];
    final enquiries =
        ref.watch(enquiriesControllerProvider).valueOrNull ?? const [];
    final name = ref.watch(userProfileProvider).value?['business_name'] ?? '';
    final now = DateTime.now();
    final brief = buildTodayBrief(orders: orders, enquiries: enquiries, now: now);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(ordersControllerProvider.notifier).load();
            await ref.read(enquiriesControllerProvider.notifier).load();
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _header(context, name, now),
              const SizedBox(height: AppSpacing.lg),
              _briefCard(brief),
              const SizedBox(height: AppSpacing.lg),
              if (brief.dueFollowUps > 0) _dueNudge(brief.dueFollowUps),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String name, DateTime now) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Closr',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
              const SizedBox(height: AppSpacing.xs),
              Text('${_greeting(now)}, $name 👋',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        ),
      ],
    );
  }

  Widget _briefCard(TodayBrief brief) {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.briefGradientStart, AppColors.briefGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Here's your business brief for today",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.md),
          row('Outstanding', Money.inr(brief.outstanding)),
          row('Follow-ups due', '${brief.dueFollowUps}'),
          row('Orders today', '${brief.ordersToday}'),
          row('Revenue today', Money.inr(brief.revenueToday)),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              onPressed: () => widget.onNavigate(1),
              child: const Text('Start My Work',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dueNudge(int count) {
    return Material(
      color: AppColors.aiSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => widget.onNavigate(1),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: AppColors.aiAccent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '$count follow-up${count == 1 ? '' : 's'} need your attention',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/today/today_screen_test.dart`
Expected: 3 tests PASS. If `find.text('₹12,000')` fails, check `Money.inr` output against the assertion (Indian grouping: `₹12,000`).

- [ ] **Step 5: Commit**

```bash
git add lib/features/today test/features/today
git commit -m "feat(today): DB-backed Today screen with brief card"
```

---

### Task 4: Business hub

Hub tab collapsing Catalog/Invoices/Profile/Go Pro (TDD §3, §4). `CatalogScreen` has no `Scaffold` of its own (it was a tab child) and its add-FAB lived on `MainScreen` — the hub pushes it wrapped so product-add stays reachable.

**Files:**
- Create: `lib/features/business/presentation/business_hub_screen.dart`
- Test: `test/features/business/business_hub_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/presentation/business_hub_screen.dart';

void main() {
  testWidgets('shows the four hub destinations', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: BusinessHubScreen()),
    ));

    expect(find.text('Business'), findsOneWidget);
    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Business Profile'), findsOneWidget);
    expect(find.text('Go Pro'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/business/business_hub_screen_test.dart`
Expected: FAIL — `business_hub_screen.dart` does not exist.

- [ ] **Step 3: Implement BusinessHubScreen**

`lib/features/business/presentation/business_hub_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/catalog/presentation/catalog_screen.dart';
import 'package:orderly_app/features/catalog/presentation/product_form_screen.dart';
import 'package:orderly_app/features/invoices/presentation/invoices_screen.dart';
import 'package:orderly_app/features/profile/presentation/profile_screen.dart';
import 'package:orderly_app/features/subscription/presentation/subscription_screen.dart';

/// Business tab: hub for everything that isn't the daily pipeline.
/// Customers entry arrives in M6; Analytics later.
class BusinessHubScreen extends StatelessWidget {
  const BusinessHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void push(Widget screen) => Navigator.push(
        context, MaterialPageRoute(builder: (_) => screen));

    final tiles = [
      (Icons.storefront_rounded, 'Catalog', 'Your products and pieces',
          () => push(const _CatalogPage())),
      (Icons.receipt_long_rounded, 'Invoices', 'Generated invoices',
          () => push(const InvoicesScreen())),
      (Icons.badge_rounded, 'Business Profile', 'Name, UPI, GST, invoice settings',
          () => push(const ProfileScreen())),
      (Icons.workspace_premium_rounded, 'Go Pro', 'Closr Pro subscription',
          () => push(const SubscriptionScreen())),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text('Business',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.lg),
            for (final (icon, title, subtitle, onTap) in tiles)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.border)),
                    leading: Icon(icon, color: AppColors.primary),
                    title: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary),
                    onTap: onTap,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// CatalogScreen is a bare tab child (no Scaffold); its add-product FAB used
/// to live on MainScreen. This wrapper keeps both when pushed as a route.
class _CatalogPage extends StatelessWidget {
  const _CatalogPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: const CatalogScreen(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProductFormScreen())),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
```

Note: if `CatalogScreen` turns out to already render inside a `Scaffold` (verify by reading its build method), drop the `_CatalogPage` wrapper and push it directly — but as of this plan it has none.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/business/business_hub_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/business/presentation/business_hub_screen.dart test/features/business/business_hub_screen_test.dart
git commit -m "feat(business): hub tab for catalog, invoices, profile, pro"
```

---

### Task 5: Bottom nav v2 (4 tabs + center capture slot)

Mock nav: Today · My Work · [+] · Orders · Business. The + is a `FloatingActionButton` docked into the center gap (wired in Task 6); `AppBottomNav` renders 4 items around a fixed-width spacer. Public API (`currentIndex`, `onTap` with indices 0–3) unchanged.

**Files:**
- Modify: `lib/shared/widgets/app_bottom_nav.dart`
- Modify: `test/shared/widgets/app_bottom_nav_test.dart`

- [ ] **Step 1: Rewrite the test (failing first)**

Replace the whole body of `test/shared/widgets/app_bottom_nav_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/app_bottom_nav.dart';

void main() {
  Widget harness({required int current, void Function(int)? onTap}) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(
          currentIndex: current,
          onTap: onTap ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('shows the four V1 tabs without overflow on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(current: 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in ['Today', 'My Work', 'Orders', 'Business']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('taps report the logical index across the center gap',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(harness(current: 0, onTap: taps.add));

    await tester.tap(find.text('Orders'));
    await tester.tap(find.text('Business'));
    expect(taps, [2, 3]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/app_bottom_nav_test.dart`
Expected: FAIL — old nav renders `Home/Enquiries/...`, `Today` not found.

- [ ] **Step 3: Update AppBottomNav**

In `lib/shared/widgets/app_bottom_nav.dart`, replace `_items` and the `Row`:

```dart
  static const List<(IconData, String)> _items = [
    (Icons.home_rounded, 'Today'),
    (Icons.checklist_rounded, 'My Work'),
    (Icons.shopping_bag_rounded, 'Orders'),
    (Icons.storefront_rounded, 'Business'),
  ];
```

```dart
        child: Row(
          children: [
            Expanded(child: _navItem(_items[0].$1, _items[0].$2, 0)),
            Expanded(child: _navItem(_items[1].$1, _items[1].$2, 1)),
            // Center gap for the docked capture FAB (MainScreen owns it).
            const SizedBox(width: 64),
            Expanded(child: _navItem(_items[2].$1, _items[2].$2, 2)),
            Expanded(child: _navItem(_items[3].$1, _items[3].$2, 3)),
          ],
        ),
```

Everything else (`_navItem`, container styling) stays.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/widgets/app_bottom_nav_test.dart`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/widgets/app_bottom_nav.dart test/shared/widgets/app_bottom_nav_test.dart
git commit -m "feat(nav): V1 four-tab bar with center capture slot"
```

---

### Task 6: MainScreen rewiring + legacy deletion

Swap the tab set, dock the capture FAB center, keep notification sync alive (legacy `leadsControllerProvider.loadLeads()` performs `syncLeadNotifications` — Dashboard used to trigger it; MainScreen takes that over until M4 replaces the engine). Then delete the Dashboard, AppHeader, StatCard, and the retired brief test.

**Files:**
- Modify: `lib/main.dart`
- Delete: `lib/features/dashboard/presentation/dashboard_screen.dart`
- Delete: `lib/shared/widgets/app_header.dart`
- Delete: `lib/shared/widgets/stat_card.dart` (only Dashboard used it)
- Delete: `test/shared/widgets/dashboard_brief_test.dart` (tests `dashboardDailyBrief` in app_header.dart, replaced by `buildTodayBrief` tests)

- [ ] **Step 1: Rewire MainScreen in `lib/main.dart`**

Replace the dashboard/catalog/invoices imports with:

```dart
import 'features/business/presentation/business_hub_screen.dart';
import 'features/leads/controller/leads_controller.dart';
import 'features/today/presentation/today_screen.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiries_screen.dart';
import 'package:orderly_app/features/enquiries/presentation/capture_screen.dart';
import 'features/orders/presentation/orders_screen.dart';
import 'features/orders/controller/orders_provider.dart';
```

(Remove now-unused imports: `dashboard_screen.dart`, `catalog_screen.dart`, `product_form_screen.dart`, `invoices_screen.dart`.)

Replace `_MainScreenState` body:

```dart
class _MainScreenState extends ConsumerState<MainScreen> {
  int currentIndex = 0;
  late final List<Widget> _screens;

  void changeTab(int index) {
    setState(() {
      currentIndex = index;
    });
    // Tabs live in an always-alive IndexedStack; refresh their data on entry
    // so captures, payments, and conversions made elsewhere show up.
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
      // Dashboard used to trigger the legacy load that syncs follow-up
      // notifications; owned here until M4 rebuilds the engine.
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
        onPressed: () {
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
```

- [ ] **Step 2: Delete the legacy files**

```bash
git rm lib/features/dashboard/presentation/dashboard_screen.dart \
       lib/shared/widgets/app_header.dart \
       lib/shared/widgets/stat_card.dart \
       test/shared/widgets/dashboard_brief_test.dart
```

- [ ] **Step 3: Fix any dangling references**

Run: `flutter analyze`
Expected: clean. If anything still imports `app_header.dart` or `stat_card.dart`, that's a missed caller — resolve it (as of this plan, only `dashboard_screen.dart` imports them; `NotificationsScreen` and `leads_controller` do NOT and stay untouched).

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: all tests pass (dashboard_brief test deleted; nav/today/business tests from earlier tasks pass).

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart   # deletions were staged by git rm in Step 2
git commit -m "feat(nav): V1 shell - Today/My Work/Orders/Business, retire Dashboard"
```

---

### Task 7: Final verification + fidelity check

- [ ] **Step 1: Full gate**

Run: `flutter analyze && flutter test`
Expected: zero issues, full suite green.

- [ ] **Step 2: Manual smoke (launch on device/simulator)**

Run: `flutter run` and walk: Today renders real numbers → Start My Work lands on enquiries → + opens capture → Orders tab loads → Business hub reaches Catalog (with add FAB), Invoices, Profile, Go Pro → bell reaches Notifications. Watch that pull-to-refresh on Today updates the brief.

- [ ] **Step 3: Fidelity note for review**

Compare Today + nav against the V1 mock side by side. Log deviations (palette confirmation pending from Raj per Task 1, robot illustration asset missing, approval queue absent until M4) in the PR/review notes — deviations need sign-off per TDD §0a, never silent.

- [ ] **Step 4: Code review**

Dispatch code-reviewer agent on the M0 diff before presenting the milestone as done.
