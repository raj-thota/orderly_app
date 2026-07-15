# Today Tab Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `TodayScreen` to match V1.0.0 mockup — AppBar with notification bell badge, 4-tile glance card with robot mascot, carousel nudge with dots, customer attention list with priority badges, AI suggested actions horizontal scroll — all wired to existing providers.

**Architecture:** Single-file rebuild of `today_screen.dart`. Private widget classes (`_StatTile`, `_AttentionTile`, `_AiActionCard`) live in the same file. All data from `workItemsProvider` + `ordersControllerProvider` + `enquiriesControllerProvider`. No new providers, no new backend calls.

**Tech Stack:** Flutter, Riverpod, existing `AppColors`/`AppSpacing`/`AppRadius`/`Money` tokens, `assets/robo.png`.

---

## File Map

| File | Change |
|---|---|
| `pubspec.yaml` | Add `- assets/robo.png` under `flutter.assets` |
| `lib/features/today/presentation/today_screen.dart` | Full rebuild |
| `test/features/today/today_screen_test.dart` | Update 2 broken tests + add 5 new |

---

### Task 1: Register robo.png asset

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add asset entry**

In `pubspec.yaml`, find the `assets:` block (around line 68) and add `robo.png`:

```yaml
  assets:
    - assets/env/default.env
    - assets/icons/
    - assets/logo/
    - assets/robo.png
```

- [ ] **Step 2: Verify flutter resolves it**

```bash
flutter pub get
```

Expected: no errors, `robo.png` listed in `.dart_tool/flutter_build/` asset manifest.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml
git commit -m "chore(assets): register robo.png for today glance card"
```

---

### Task 2: Update and extend today_screen tests

**Files:**
- Modify: `test/features/today/today_screen_test.dart`

The existing test `shows pending approvals count when work items exist` checks `find.textContaining('approval')` — this breaks when the section is renamed to "Needs your attention". The test `Start My Work navigates to tab 1` checks `find.text('Start My Work')` — the button text becomes `'Start My Work →'`.

- [ ] **Step 1: Write the updated + new test file**

Replace `test/features/today/today_screen_test.dart` with:

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
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

import '../work/work_items_provider_test.dart' show FakeAiWorkItemsService;

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

Widget _harness({
  List<Order> orders = const [],
  List<Enquiry> enquiries = const [],
  List<String>? events,
  void Function(int)? onNavigate,
  FakeAiWorkItemsService? workItems,
}) {
  final captured = events ?? [];
  return ProviderScope(
    overrides: [
      ordersControllerProvider.overrideWith((ref) => _FixedOrders(orders)),
      enquiriesControllerProvider
          .overrideWith((ref) => _FixedEnquiries(enquiries)),
      userProfileProvider
          .overrideWith((ref) async => {'business_name': 'Raj'}),
      eventServiceProvider.overrideWithValue(EventService(
        sink: (row) async => captured.add(row['name'] as String),
        currentUserId: () => 'u1',
      )),
      aiWorkItemsServiceProvider
          .overrideWithValue(workItems ?? FakeAiWorkItemsService([])),
    ],
    child: MaterialApp(
      home: TodayScreen(onNavigate: onNavigate ?? (_) {}),
    ),
  );
}

final _dueEnquiry = Enquiry(
  status: 'follow',
  followUpDate: DateTime.now().subtract(const Duration(days: 1)),
  customerName: 'Meena',
);

AiWorkItem _workItem({
  String id = '1',
  String kind = 'payment_reminder',
  String priority = 'high',
  String? customerName,
  double? amount,
}) =>
    AiWorkItem(
      id: id,
      kind: kind,
      priority: priority,
      score: 90,
      title: 'Payment pending',
      status: 'pending',
      batchId: 'b-1',
      customerId: 'c-1',
      customerName: customerName,
      amount: amount,
    );

void main() {
  // ── Existing: brief numbers ──────────────────────────────────────────────
  testWidgets('renders brief stat tile values from orders and enquiries',
      (t) async {
    final orders = [
      Order(grandTotal: 9500, payments: [
        Payment(amount: 9500, paidAt: DateTime.now()),
      ], createdAt: DateTime.now()),
      const Order(grandTotal: 12000), // outstanding
    ];
    await t.pumpWidget(_harness(orders: orders, enquiries: [_dueEnquiry]));
    await t.pumpAndSettle();

    expect(find.text('₹12,000'), findsOneWidget); // outstanding tile
    expect(find.text('₹9,500'), findsOneWidget);  // revenue tile
    expect(find.textContaining('Raj'), findsOneWidget);
    expect(find.textContaining('Start My Work'), findsOneWidget);
  });

  // ── Existing: Start My Work navigation ──────────────────────────────────
  testWidgets('Start My Work button navigates to tab 1', (t) async {
    int? navigated;
    await t.pumpWidget(_harness(onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.tap(find.textContaining('Start My Work'));
    expect(navigated, 1);
  });

  // ── Existing: event tracking ─────────────────────────────────────────────
  testWidgets('tracks brief_view once on open', (t) async {
    final events = <String>[];
    await t.pumpWidget(_harness(events: events));
    await t.pumpAndSettle();
    expect(events, ['brief_view']);
  });

  // ── Existing: nudge navigation ───────────────────────────────────────────
  testWidgets('due nudge tap navigates to tab 1', (t) async {
    int? navigated;
    await t.pumpWidget(_harness(
        enquiries: [_dueEnquiry],
        onNavigate: (i) => navigated = i));
    await t.pumpAndSettle();

    await t.tap(find.textContaining('need your attention'));
    expect(navigated, 1);
  });

  // ── Updated: work items section uses new label ────────────────────────────
  testWidgets('shows Needs your attention section when work items exist',
      (t) async {
    final svc = FakeAiWorkItemsService([_workItem(customerName: 'Priya')]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text('Needs your attention'), findsOneWidget);
  });

  // ── New: AppBar notification bell badge ──────────────────────────────────
  testWidgets('bell badge shows pending work item count', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(id: '1'),
      _workItem(id: '2'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.text('2'), findsOneWidget); // badge count
  });

  // ── New: attention tile content ──────────────────────────────────────────
  testWidgets('attention tile shows customer name and priority badge', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Rekha Joshi', priority: 'high'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.textContaining('Rekha Joshi'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
  });

  // ── New: attention tile amount ────────────────────────────────────────────
  testWidgets('attention tile shows formatted amount', (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Aman', amount: 3360),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.textContaining('₹3,360'), findsOneWidget);
  });

  // ── New: AI actions section ──────────────────────────────────────────────
  testWidgets('AI suggested actions section visible when work items exist',
      (t) async {
    final svc = FakeAiWorkItemsService([
      _workItem(customerName: 'Deepika', kind: 'follow_up'),
    ]);
    await t.pumpWidget(_harness(workItems: svc));
    await t.pumpAndSettle();

    expect(find.textContaining('AI suggested actions'), findsOneWidget);
    expect(find.textContaining('Call follow-up for Deepika'), findsOneWidget);
  });

  // ── New: no nudge when everything zero ───────────────────────────────────
  testWidgets('nudge section hidden when brief has no items', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.textContaining('need your attention'), findsNothing);
    expect(find.textContaining('outstanding'), findsNothing);
  });

  // ── New: glance card stat labels present ─────────────────────────────────
  testWidgets('glance card shows all 4 stat tile labels', (t) async {
    await t.pumpWidget(_harness());
    await t.pumpAndSettle();

    expect(find.textContaining('Follow-ups'), findsOneWidget);
    expect(find.textContaining('Orders'), findsOneWidget);
    expect(find.textContaining('Revenue'), findsOneWidget);
    expect(find.textContaining('Outstanding'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests — expect failures (screen not rebuilt yet)**

```bash
flutter test test/features/today/today_screen_test.dart --reporter compact
```

Expected: Several failures — `'Start My Work'` exact text not found; `'approval'` test gone; new tests fail because sections don't exist yet. This is correct — tests drive the implementation.

- [ ] **Step 3: Commit failing tests**

```bash
git add test/features/today/today_screen_test.dart
git commit -m "test(today): update + extend today screen tests for V1 redesign"
```

---

### Task 3: Rebuild today_screen.dart — AppBar + Glance Card

**Files:**
- Rebuild: `lib/features/today/presentation/today_screen.dart`

- [ ] **Step 1: Replace file with new scaffold + AppBar + glance card**

Write `lib/features/today/presentation/today_screen.dart`:

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
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, required this.onNavigate});

  final void Function(int tab) onNavigate;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late final PageController _nudgePageCtrl;
  int _nudgePage = 0;

  @override
  void initState() {
    super.initState();
    _nudgePageCtrl = PageController();
    Future.microtask(() {
      ref.read(eventServiceProvider).track('brief_view');
      ref.read(workItemsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _nudgePageCtrl.dispose();
    super.dispose();
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    return 'Today';
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _actionLabel(String kind) {
    switch (kind) {
      case 'payment_reminder':
      case 'overdue_payment':
        return 'Send Reminder';
      case 'follow_up':
      case 'call':
        return 'Follow Up';
      default:
        return 'Message';
    }
  }

  String _actionCta(String kind) {
    switch (kind) {
      case 'payment_reminder':
      case 'overdue_payment':
        return 'Send Now';
      case 'follow_up':
      case 'call':
        return 'Call Now';
      case 'share_catalog':
      case 'offer':
        return 'Create Offer';
      default:
        return 'Message';
    }
  }

  String _actionDescription(AiWorkItem item) {
    final name = item.customerName ?? 'Customer';
    switch (item.kind) {
      case 'payment_reminder':
      case 'overdue_payment':
        return 'Send price to $name';
      case 'follow_up':
      case 'call':
        return 'Call follow-up for $name';
      case 'share_catalog':
      case 'offer':
        return 'Offer discount to $name';
      default:
        return 'Message $name';
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders =
        ref.watch(ordersControllerProvider).valueOrNull ?? const [];
    final enquiries =
        ref.watch(enquiriesControllerProvider).valueOrNull ?? const [];
    final name =
        ref.watch(userProfileProvider).value?['business_name'] ?? '';
    final now = DateTime.now();
    final brief =
        buildTodayBrief(orders: orders, enquiries: enquiries, now: now);
    final workState = ref.watch(workItemsProvider);
    final nudges = _buildNudges(brief);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _appBar(workState.pendingCount),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(ordersControllerProvider.notifier).load();
            await ref.read(enquiriesControllerProvider.notifier).load();
            await ref.read(workItemsProvider.notifier).load();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
            children: [
              Text(
                '${_greeting(now)}, $name 👋',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                "Here's what's happening with your business today.",
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              _glanceCard(brief),
              if (nudges.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _nudgeSection(nudges),
              ],
              if (workState.items.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                _attentionSection(workState),
                const SizedBox(height: AppSpacing.xl),
                _aiActionsSection(workState),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _appBar(int badgeCount) => AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 4),
            const Text(
              'Closr',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationsScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: Stack(
                alignment: Alignment.topRight,
                clipBehavior: Clip.none,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 4),
                    child: Icon(Icons.notifications_outlined,
                        color: AppColors.textPrimary, size: 26),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );

  // ── Glance Card ───────────────────────────────────────────────────────────

  Widget _glanceCard(TodayBrief brief) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AppColors.briefGradientStart,
              AppColors.briefGradientEnd
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today at a glance',
                style:
                    TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: AppSpacing.md),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  children: [
                    _StatTile(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Follow-ups\ndue',
                      value: '${brief.dueFollowUps}',
                      badgeText: brief.dueFollowUps > 0
                          ? 'Needs attention'
                          : 'All caught up',
                      badgeColor: brief.dueFollowUps > 0
                          ? AppColors.danger
                          : AppColors.success,
                    ),
                    _StatTile(
                      icon: Icons.shopping_bag_outlined,
                      label: 'Orders\ntoday',
                      value: '${brief.ordersToday}',
                      badgeText: brief.ordersToday > 0
                          ? 'New order'
                          : 'No orders',
                      badgeColor: brief.ordersToday > 0
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    _StatTile(
                      icon: Icons.currency_rupee_rounded,
                      label: 'Revenue\ntoday',
                      value: brief.revenueToday > 0
                          ? Money.inr(brief.revenueToday)
                          : '₹0',
                      badgeText: brief.revenueToday > 0
                          ? 'Sales today'
                          : 'No sales yet',
                      badgeColor: brief.revenueToday > 0
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    _StatTile(
                      icon: Icons.layers_outlined,
                      label: 'Outstanding',
                      value: Money.inr(brief.outstanding),
                      badgeText: 'Total due',
                      badgeColor: AppColors.info,
                    ),
                    const SizedBox(width: 80),
                  ],
                ),
                Positioned(
                  right: -AppSpacing.lg,
                  top: -AppSpacing.lg,
                  child: Image.asset(
                    'assets/robo.png',
                    height: 110,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                ),
                onPressed: () => widget.onNavigate(1),
                child: const Text('Start My Work →',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );

  // ── Nudge Carousel ────────────────────────────────────────────────────────

  List<_NudgeData> _buildNudges(TodayBrief brief) {
    final nudges = <_NudgeData>[];
    if (brief.dueFollowUps > 0) {
      nudges.add(_NudgeData(
        icon: Icons.schedule_rounded,
        title:
            '${brief.dueFollowUps} follow-up${brief.dueFollowUps == 1 ? '' : 's'} need your attention',
        subtitle: 'Review and take action',
        onTap: () => widget.onNavigate(1),
      ));
    }
    if (brief.outstanding > 0) {
      nudges.add(_NudgeData(
        icon: Icons.currency_rupee_rounded,
        title: '${Money.inr(brief.outstanding)} outstanding payments',
        subtitle: 'Collect payments now',
        onTap: () => widget.onNavigate(2),
      ));
    }
    if (brief.ordersToday > 0) {
      nudges.add(_NudgeData(
        icon: Icons.shopping_bag_outlined,
        title:
            '${brief.ordersToday} new order${brief.ordersToday == 1 ? '' : 's'} placed today',
        subtitle: 'View your orders',
        onTap: () => widget.onNavigate(2),
      ));
    }
    return nudges;
  }

  Widget _nudgeSection(List<_NudgeData> nudges) => Column(
        children: [
          SizedBox(
            height: 88,
            child: PageView.builder(
              controller: _nudgePageCtrl,
              onPageChanged: (i) => setState(() => _nudgePage = i),
              itemCount: nudges.length,
              itemBuilder: (_, i) {
                final n = nudges[i];
                return Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: n.onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.aiSurface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(n.icon,
                                color: AppColors.aiAccent),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Text(n.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                        fontSize: 14)),
                                Text(n.subtitle,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (nudges.length > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(nudges.length, (i) {
                final active = i == _nudgePage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: active ? 20 : 6,
                  height: 6,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary
                        : AppColors.border,
                    borderRadius:
                        BorderRadius.circular(AppRadius.pill),
                  ),
                );
              }),
            ),
          ],
        ],
      );

  // ── Attention Section ─────────────────────────────────────────────────────

  Widget _attentionSection(WorkItemsState workState) {
    final items = workState.items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Needs your attention',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            TextButton(
              onPressed: () => widget.onNavigate(1),
              child: Text(
                'View all (${workState.pendingCount})',
                style: const TextStyle(
                    color: AppColors.primary, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final item in items) ...[
          _AttentionTile(
            item: item,
            initials: _initials(item.customerName),
            timeAgo: _timeAgo(item.createdAt),
            actionLabel: _actionLabel(item.kind),
            onTap: () => widget.onNavigate(1),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  // ── AI Actions Section ────────────────────────────────────────────────────

  Widget _aiActionsSection(WorkItemsState workState) {
    final items = workState.items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 14, color: AppColors.primary),
                SizedBox(width: 4),
                Text('AI suggested actions',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
            TextButton(
              onPressed: () => widget.onNavigate(1),
              child: const Text('View all',
                  style: TextStyle(
                      color: AppColors.primary, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in items) ...[
                _AiActionCard(
                  item: item,
                  actionDescription: _actionDescription(item),
                  actionCta: _actionCta(item.kind),
                  onTap: () => widget.onNavigate(1),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Private data class ────────────────────────────────────────────────────────

class _NudgeData {
  const _NudgeData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

// ── _StatTile ─────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.badgeText,
    required this.badgeColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String badgeText;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style:
                const TextStyle(color: Colors.white70, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                  color: badgeColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _AttentionTile ────────────────────────────────────────────────────────────

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.item,
    required this.initials,
    required this.timeAgo,
    required this.actionLabel,
    required this.onTap,
  });

  final AiWorkItem item;
  final String initials;
  final String timeAgo;
  final String actionLabel;
  final VoidCallback onTap;

  Color _priorityColor() {
    switch (item.priority) {
      case 'high':
        return AppColors.danger;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String _priorityLabel() =>
      item.priority[0].toUpperCase() + item.priority.substring(1);

  @override
  Widget build(BuildContext context) {
    final pc = _priorityColor();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.aiSurface,
                child: Text(
                  initials,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.customerName ?? 'Customer',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: pc.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            _priorityLabel(),
                            style: TextStyle(
                                color: pc,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      item.context ?? item.title,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (timeAgo.isNotEmpty)
                      Text(
                        timeAgo,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.amount != null)
                    Text(
                      Money.inr(item.amount!),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textPrimary),
                    ),
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 32),
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm)),
                    ),
                    child: Text(
                      actionLabel,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _AiActionCard ─────────────────────────────────────────────────────────────

class _AiActionCard extends StatelessWidget {
  const _AiActionCard({
    required this.item,
    required this.actionDescription,
    required this.actionCta,
    required this.onTap,
  });

  final AiWorkItem item;
  final String actionDescription;
  final String actionCta;
  final VoidCallback onTap;

  (IconData, Color) _iconAndColor() {
    switch (item.kind) {
      case 'payment_reminder':
      case 'overdue_payment':
        return (Icons.chat_rounded, const Color(0xFF25D366));
      case 'follow_up':
      case 'call':
        return (Icons.phone_outlined, AppColors.primary);
      case 'share_catalog':
      case 'offer':
        return (Icons.card_giftcard_outlined, AppColors.warning);
      default:
        return (Icons.message_outlined, AppColors.aiAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconAndColor();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              actionDescription,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$actionCta →',
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run tests**

```bash
flutter test test/features/today/today_screen_test.dart --reporter compact
```

Expected: All 12 tests pass. If `Image.asset('assets/robo.png')` throws in tests, add `TestWidgetsFlutterBinding.ensureInitialized()` or mock the asset — but Flutter widget tests skip missing asset rendering by default, so this is usually fine.

- [ ] **Step 3: Run full test suite to check no regressions**

```bash
flutter test --reporter compact
```

Expected: All tests pass (today_brief_test.dart untouched, other feature tests unaffected).

- [ ] **Step 4: Commit**

```bash
git add lib/features/today/presentation/today_screen.dart
git commit -m "feat(today): V1 redesign — glance card, carousel nudge, attention list, AI actions"
```

---

### Task 4: Verify on device / simulator

**Files:** None (verification only)

- [ ] **Step 1: Run app**

```bash
flutter run
```

- [ ] **Step 2: Check each section**

1. AppBar shows sparkle + "Closr" centered; bell icon visible; badge count = pending work items (0 if DB empty)
2. Greeting + subtitle below AppBar
3. "Today at a glance" card: 4 tiles visible, `robo.png` overlaps top-right, "Start My Work →" button
4. If any orders with dues OR dueFollowUps > 0: nudge card appears with pagination dots (if multiple)
5. If AI work items exist in DB: "Needs your attention" + "AI suggested actions" sections appear
6. Bell icon tap opens `NotificationsScreen`
7. "Start My Work →" and all "View all" / action buttons navigate to correct tabs
8. Pull-to-refresh reloads all data

- [ ] **Step 3: Final commit if any pixel tweaks made**

```bash
git add lib/features/today/presentation/today_screen.dart
git commit -m "fix(today): visual tweaks from device verification"
```
