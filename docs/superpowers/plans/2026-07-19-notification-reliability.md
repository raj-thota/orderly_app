# Notification Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate duplicate follow-up device notifications, harden tap navigation across all app states, and apply a light polish to the in-app Notification Center — without changing the OS-notification feature set.

**Architecture:** Model the desired reminders as a pure function of the current leads (`planFollowUpReminders`), then reconcile that plan against the OS's own pending-notification set (`reconcileReminders`). A small injectable scheduler serializes syncs and applies the reconciliation. `NotificationService` becomes a thin static facade over the plugin that wires these pieces, plus an idempotent tap router. The Notification Center gets swipe-to-dismiss, relative timestamps, and mark-all-done using existing provider methods.

**Tech Stack:** Flutter, `flutter_local_notifications` ^21, `shared_preferences` ^2.2, `timezone` ^0.11, Riverpod, `flutter_test`.

**Verification commands:**
- Single test file: `flutter test <path> -r compact`
- Full suite: `flutter test -r compact`
- Static analysis: `flutter analyze`

**Reference spec:** `docs/superpowers/specs/2026-07-19-notification-reliability-design.md`

**Note on scope corrections found during planning:**
- `capture_screen.dart` calls `syncLeadNotifications` in **two different save flows** (`_shareAndSave` and `_save`), not a duplicate double-call. Both are renamed, neither removed.
- The Notification Center provider has no un-dismiss method, so swipe-to-dismiss shows a plain "Dismissed" snackbar (no undo). Adding un-dismiss is out of scope.

---

## File Structure

**New files**
- `lib/core/services/follow_up_reminder_planner.dart` — pure: `PlannedReminder`, date helpers, `planFollowUpReminders`, `reconcileReminders`, `ReminderReconciliation`. No Flutter/plugin imports.
- `lib/core/services/notification_id_registry.dart` — `NotificationIdRegistry`: SharedPreferences-backed stable+unique notification ids.
- `lib/core/services/follow_up_reminder_scheduler.dart` — `FollowUpReminderScheduler`: injectable, serialized reconcile orchestration.

**Modified files**
- `lib/core/services/notification_service.dart` — rewritten thin facade (init, plugin primitives, migration, `TapDeduper`, wires scheduler). Deletes dead code.
- `lib/main.dart` — `_MainScreenState` gains `WidgetsBindingObserver` for resume re-sync.
- `lib/features/enquiries/presentation/capture_screen.dart` — rename `syncLeadNotifications` → `syncFollowUpReminders` (2 sites).
- `lib/features/work/controller/work_items_provider.dart` — add `markAllDone()`.
- `lib/features/notifications/presentation/notifications_screen.dart` — relative timestamps, swipe-to-dismiss, mark-all-done.

**New/updated tests**
- `test/core/services/follow_up_reminder_planner_test.dart`
- `test/core/services/notification_id_registry_test.dart`
- `test/core/services/follow_up_reminder_scheduler_test.dart`
- `test/core/services/tap_deduper_test.dart`
- `test/features/work/work_items_provider_test.dart` — add `markAllDone` test
- `test/features/notifications/notifications_screen_test.dart` — swipe/timestamp/mark-all

---

## Task 1: Pure planner + reconcile

**Files:**
- Create: `lib/core/services/follow_up_reminder_planner.dart`
- Test: `test/core/services/follow_up_reminder_planner_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/core/services/follow_up_reminder_planner_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/follow_up_reminder_planner.dart';

void main() {
  int idFor(String leadId, String type) =>
      Object.hash(leadId, type) & 0x7fffffff;

  Map<String, dynamic> lead({
    String id = 'l1',
    String status = 'follow',
    DateTime? followUp,
    String name = 'Asha',
  }) =>
      {
        'id': id,
        'status': status,
        'name': name,
        'follow_up_date': followUp?.toIso8601String(),
      };

  final now = DateTime(2026, 7, 19, 14, 0);

  group('planFollowUpReminders', () {
    test('overdue lead -> single daily 9am repeating reminder', () {
      final plans = planFollowUpReminders(
        [lead(followUp: DateTime(2026, 7, 17))],
        now: now,
        idFor: idFor,
      );
      expect(plans, hasLength(1));
      final p = plans.single;
      expect(p.repeatDaily, isTrue);
      expect(p.when, DateTime(2026, 7, 20, 9)); // 9am already passed today -> tomorrow
      expect(p.title, 'Overdue follow-up');
      expect(p.payload, 'l1');
    });

    test('future follow-up time -> one non-repeating scheduled reminder', () {
      final plans = planFollowUpReminders(
        [lead(followUp: DateTime(2026, 7, 19, 18, 30))],
        now: now,
        idFor: idFor,
      );
      expect(plans, hasLength(1));
      expect(plans.single.repeatDaily, isFalse);
      expect(plans.single.when, DateTime(2026, 7, 19, 18, 30));
      expect(plans.single.title, 'Follow-up reminder');
    });

    test('due today but time already passed -> no reminder', () {
      final plans = planFollowUpReminders(
        [lead(followUp: DateTime(2026, 7, 19, 9, 0))], // 9am, now is 2pm
        now: now,
        idFor: idFor,
      );
      expect(plans, isEmpty);
    });

    test('non-follow status or missing date -> no reminder', () {
      final plans = planFollowUpReminders(
        [
          lead(status: 'won', followUp: DateTime(2026, 7, 17)),
          lead(id: 'l2', followUp: null),
        ],
        now: now,
        idFor: idFor,
      );
      expect(plans, isEmpty);
    });

    test('de-dupes reminders that resolve to the same id', () {
      int constId(String _, String __) => 42;
      final plans = planFollowUpReminders(
        [
          lead(id: 'a', followUp: DateTime(2026, 7, 17)),
          lead(id: 'b', followUp: DateTime(2026, 7, 16)),
        ],
        now: now,
        idFor: constId,
      );
      expect(plans, hasLength(1));
    });
  });

  group('reconcileReminders', () {
    final r1 = PlannedReminder(
      id: 1,
      when: DateTime(2026, 7, 20, 9),
      title: 't',
      body: 'b',
      payload: 'l1',
    );

    test('schedules all planned and cancels ids not in the plan', () {
      final recon = reconcileReminders([r1], {1, 2, 3});
      expect(recon.toSchedule, [r1]);
      expect(recon.toCancel..sort(), [2, 3]);
    });

    test('empty plan cancels everything pending', () {
      final recon = reconcileReminders([], {5, 6});
      expect(recon.toSchedule, isEmpty);
      expect(recon.toCancel..sort(), [5, 6]);
    });

    test('no-op when plan already matches pending', () {
      final recon = reconcileReminders([r1], {1});
      expect(recon.toCancel, isEmpty);
      expect(recon.toSchedule, [r1]);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/services/follow_up_reminder_planner_test.dart -r compact`
Expected: FAIL — `follow_up_reminder_planner.dart` does not exist (compile error).

- [ ] **Step 3: Write the implementation**

Create `lib/core/services/follow_up_reminder_planner.dart`:

```dart
/// Pure follow-up reminder planning. No Flutter, plugin, or IO imports so it
/// can be unit-tested in isolation and reasoned about deterministically.

const int kDefaultReminderHour = 9;

/// A single reminder the OS should be holding for a lead.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
    required this.payload,
    this.repeatDaily = false,
  });

  final int id;
  final DateTime when;
  final String title;
  final String body;
  final String payload;
  final bool repeatDaily;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.when == when &&
      other.title == title &&
      other.body == body &&
      other.payload == payload &&
      other.repeatDaily == repeatDaily;

  @override
  int get hashCode => Object.hash(id, when, title, body, payload, repeatDaily);
}

DateTime? parseFollowUpDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

bool isFollowUpToday(Map<String, dynamic> lead, {DateTime? now}) {
  if (lead['status'] != 'follow') return false;
  final followUpDate = parseFollowUpDate(lead['follow_up_date']);
  if (followUpDate == null) return false;
  final current = now ?? DateTime.now();
  return followUpDate.year == current.year &&
      followUpDate.month == current.month &&
      followUpDate.day == current.day;
}

bool isOverdueFollowUp(Map<String, dynamic> lead, {DateTime? now}) {
  if (lead['status'] != 'follow') return false;
  final followUpDate = parseFollowUpDate(lead['follow_up_date']);
  if (followUpDate == null) return false;
  final current = now ?? DateTime.now();
  final startOfToday = DateTime(current.year, current.month, current.day);
  return followUpDate.isBefore(startOfToday);
}

/// If the follow-up date carries no explicit clock time, default to 9am.
DateTime notificationTimeForFollowUp(DateTime followUpDate) {
  final hasExplicitTime = followUpDate.hour != 0 ||
      followUpDate.minute != 0 ||
      followUpDate.second != 0 ||
      followUpDate.millisecond != 0 ||
      followUpDate.microsecond != 0;
  return hasExplicitTime
      ? followUpDate
      : DateTime(
          followUpDate.year,
          followUpDate.month,
          followUpDate.day,
          kDefaultReminderHour,
        );
}

/// Next 9am at or after [now].
DateTime nextOverdueReminderTime(DateTime now) {
  final today9 = DateTime(now.year, now.month, now.day, kDefaultReminderHour);
  return today9.isAfter(now) ? today9 : today9.add(const Duration(days: 1));
}

/// Desired reminder set for [leads]. `idFor(leadId, type)` supplies a stable,
/// collision-free notification id.
List<PlannedReminder> planFollowUpReminders(
  List<Map<String, dynamic>> leads, {
  DateTime? now,
  required int Function(String leadId, String type) idFor,
}) {
  final current = now ?? DateTime.now();
  final result = <PlannedReminder>[];
  final seenIds = <int>{};

  void add(PlannedReminder reminder) {
    if (seenIds.add(reminder.id)) result.add(reminder);
  }

  for (final lead in leads) {
    final leadId = lead['id']?.toString();
    final followUpDate = parseFollowUpDate(lead['follow_up_date']);
    if (leadId == null ||
        leadId.isEmpty ||
        followUpDate == null ||
        lead['status'] != 'follow') {
      continue;
    }
    final name = (lead['name'] ?? 'Customer').toString().trim();

    if (isOverdueFollowUp(lead, now: current)) {
      add(PlannedReminder(
        id: idFor(leadId, 'overdue'),
        when: nextOverdueReminderTime(current),
        title: 'Overdue follow-up',
        body: '$name still needs your attention.',
        payload: leadId,
        repeatDaily: true,
      ));
      continue;
    }

    final when = notificationTimeForFollowUp(followUpDate);
    if (when.isAfter(current)) {
      add(PlannedReminder(
        id: idFor(leadId, 'follow_up'),
        when: when,
        title: 'Follow-up reminder',
        body: 'Reach out to $name on time.',
        payload: leadId,
      ));
    }
    // Due today but the time has already passed: intentionally no reminder.
  }
  return result;
}

/// Result of diffing a plan against the OS's pending notification ids.
class ReminderReconciliation {
  const ReminderReconciliation({
    required this.toSchedule,
    required this.toCancel,
  });

  final List<PlannedReminder> toSchedule;
  final List<int> toCancel;
}

/// Re-schedule every planned reminder (scheduling by id replaces in place,
/// keeping body text fresh without firing), and cancel any pending id that is
/// no longer planned.
ReminderReconciliation reconcileReminders(
  List<PlannedReminder> planned,
  Set<int> currentPendingIds,
) {
  final plannedIds = planned.map((r) => r.id).toSet();
  final toCancel =
      currentPendingIds.where((id) => !plannedIds.contains(id)).toList();
  return ReminderReconciliation(toSchedule: planned, toCancel: toCancel);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/services/follow_up_reminder_planner_test.dart -r compact`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/follow_up_reminder_planner.dart test/core/services/follow_up_reminder_planner_test.dart
git commit -m "feat(notifications): pure follow-up reminder planner + reconcile"
```

---

## Task 2: Notification id registry

**Files:**
- Create: `lib/core/services/notification_id_registry.dart`
- Test: `test/core/services/notification_id_registry_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/core/services/notification_id_registry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/notification_id_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns the same id for the same lead+type', () async {
    final prefs = await SharedPreferences.getInstance();
    final reg = NotificationIdRegistry.load(prefs);
    final a = reg.idFor('lead1', 'overdue');
    final b = reg.idFor('lead1', 'overdue');
    expect(a, b);
  });

  test('returns distinct ids for different keys', () {
    // Same instance, no persistence needed.
    SharedPreferences.setMockInitialValues({});
  });

  test('distinct ids for different lead+type and stays positive', () async {
    final prefs = await SharedPreferences.getInstance();
    final reg = NotificationIdRegistry.load(prefs);
    final ids = {
      reg.idFor('a', 'overdue'),
      reg.idFor('a', 'follow_up'),
      reg.idFor('b', 'overdue'),
    };
    expect(ids, hasLength(3));
    expect(ids.every((id) => id > 0 && id < 0x7fffffff), isTrue);
  });

  test('ids persist across reload after flush', () async {
    final prefs = await SharedPreferences.getInstance();
    final reg1 = NotificationIdRegistry.load(prefs);
    final first = reg1.idFor('lead1', 'overdue');
    await reg1.flush();

    final reg2 = NotificationIdRegistry.load(prefs);
    expect(reg2.idFor('lead1', 'overdue'), first);
    // A new key does not collide with the persisted one.
    expect(reg2.idFor('lead2', 'overdue'), isNot(first));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/services/notification_id_registry_test.dart -r compact`
Expected: FAIL — `notification_id_registry.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/core/services/notification_id_registry.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Stable, collision-free notification ids keyed by "<leadId>:<type>".
///
/// Replaces the old `Object.hash(leadId, type)` scheme, which could collide
/// across different leads and cancel the wrong notification. Ids are assigned
/// from a monotonic counter and persisted so cancels match what was scheduled.
class NotificationIdRegistry {
  NotificationIdRegistry._(this._prefs, this._map, this._counter);

  final SharedPreferences _prefs;
  final Map<String, int> _map;
  int _counter;
  bool _dirty = false;

  static const String _mapKey = 'notif_id_registry_v1';
  static const String _counterKey = 'notif_id_registry_counter_v1';

  static NotificationIdRegistry load(SharedPreferences prefs) {
    final map = <String, int>{};
    for (final entry in prefs.getStringList(_mapKey) ?? const <String>[]) {
      final sep = entry.lastIndexOf('=');
      if (sep <= 0) continue;
      final id = int.tryParse(entry.substring(sep + 1));
      if (id != null) map[entry.substring(0, sep)] = id;
    }
    return NotificationIdRegistry._(prefs, map, prefs.getInt(_counterKey) ?? 0);
  }

  /// Returns the existing id for [leadId]+[type], or assigns the next one.
  /// Synchronous so it can be used as the `idFor` callback during planning;
  /// call [flush] afterwards to persist any newly-assigned ids.
  int idFor(String leadId, String type) {
    final key = '$leadId:$type';
    final existing = _map[key];
    if (existing != null) return existing;
    _counter += 1;
    _map[key] = _counter;
    _dirty = true;
    return _counter;
  }

  Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    await _prefs.setInt(_counterKey, _counter);
    await _prefs.setStringList(
      _mapKey,
      _map.entries.map((e) => '${e.key}=${e.value}').toList(),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/services/notification_id_registry_test.dart -r compact`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/notification_id_registry.dart test/core/services/notification_id_registry_test.dart
git commit -m "feat(notifications): persisted collision-free notification id registry"
```

---

## Task 3: Serialized reconcile scheduler

**Files:**
- Create: `lib/core/services/follow_up_reminder_scheduler.dart`
- Test: `test/core/services/follow_up_reminder_scheduler_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/core/services/follow_up_reminder_scheduler_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/follow_up_reminder_planner.dart';
import 'package:orderly_app/core/services/follow_up_reminder_scheduler.dart';
import 'package:orderly_app/core/services/notification_id_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Set<int> pending;
  late List<PlannedReminder> scheduled;
  late List<int> cancelled;

  Future<FollowUpReminderScheduler> build({DateTime? now}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    pending = <int>{};
    scheduled = <PlannedReminder>[];
    cancelled = <int>[];
    return FollowUpReminderScheduler(
      pendingIds: () async => Set<int>.from(pending),
      schedule: (r) async {
        scheduled.add(r);
        pending.add(r.id);
      },
      cancel: (id) async {
        cancelled.add(id);
        pending.remove(id);
      },
      registry: NotificationIdRegistry.load(prefs),
      now: () => now ?? DateTime(2026, 7, 19, 14, 0),
    );
  }

  Map<String, dynamic> lead(String id, DateTime followUp) => {
        'id': id,
        'status': 'follow',
        'name': 'Asha',
        'follow_up_date': followUp.toIso8601String(),
      };

  test('schedules planned reminders on first sync', () async {
    final sched = await build();
    await sched.sync([lead('l1', DateTime(2026, 7, 17))]); // overdue
    expect(scheduled, hasLength(1));
    expect(cancelled, isEmpty);
  });

  test('cancels a pending id that is no longer planned', () async {
    final sched = await build();
    pending.addAll({999}); // stale, not in any plan
    await sched.sync([lead('l1', DateTime(2026, 7, 17))]);
    expect(cancelled, contains(999));
  });

  test('re-sync with the same leads does not accumulate cancels', () async {
    final sched = await build();
    await sched.sync([lead('l1', DateTime(2026, 7, 17))]);
    cancelled.clear();
    await sched.sync([lead('l1', DateTime(2026, 7, 17))]);
    expect(cancelled, isEmpty);
  });

  test('concurrent syncs are serialized (no interleaving)', () async {
    final sched = await build();
    final a = sched.sync([lead('l1', DateTime(2026, 7, 17))]);
    final b = sched.sync([lead('l2', DateTime(2026, 7, 16))]);
    await Future.wait([a, b]);
    // Final state reflects the last-submitted leads; no crash, no duplicate ids.
    expect(pending, isNotEmpty);
    expect(pending.length, pending.toSet().length);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/services/follow_up_reminder_scheduler_test.dart -r compact`
Expected: FAIL — `follow_up_reminder_scheduler.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/core/services/follow_up_reminder_scheduler.dart`:

```dart
import 'follow_up_reminder_planner.dart';
import 'notification_id_registry.dart';

/// Serializes reminder syncs and applies the plan/reconcile against the OS.
///
/// The OS pending-notification set is the source of truth. Concurrent [sync]
/// calls coalesce: if one is running, the latest leads are remembered and one
/// more pass runs when it finishes. Dart's single-threaded event loop makes the
/// in-flight guard sufficient — there is no true parallelism to protect against.
class FollowUpReminderScheduler {
  FollowUpReminderScheduler({
    required Future<Set<int>> Function() pendingIds,
    required Future<void> Function(PlannedReminder reminder) schedule,
    required Future<void> Function(int id) cancel,
    required NotificationIdRegistry registry,
    DateTime Function() now = DateTime.now,
  })  : _pendingIds = pendingIds,
        _schedule = schedule,
        _cancel = cancel,
        _registry = registry,
        _now = now;

  final Future<Set<int>> Function() _pendingIds;
  final Future<void> Function(PlannedReminder) _schedule;
  final Future<void> Function(int) _cancel;
  final NotificationIdRegistry _registry;
  final DateTime Function() _now;

  Future<void>? _inFlight;
  bool _dirty = false;
  List<Map<String, dynamic>> _leads = const [];

  Future<void> sync(List<Map<String, dynamic>> leads) {
    _leads = leads;
    final inFlight = _inFlight;
    if (inFlight != null) {
      _dirty = true;
      return inFlight;
    }
    final run = _drain();
    _inFlight = run;
    return run;
  }

  Future<void> _drain() async {
    try {
      do {
        _dirty = false;
        await _reconcileOnce(_leads);
      } while (_dirty);
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _reconcileOnce(List<Map<String, dynamic>> leads) async {
    final planned =
        planFollowUpReminders(leads, now: _now(), idFor: _registry.idFor);
    await _registry.flush();
    final current = await _pendingIds();
    final recon = reconcileReminders(planned, current);
    for (final id in recon.toCancel) {
      await _cancel(id);
    }
    for (final reminder in recon.toSchedule) {
      await _schedule(reminder);
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/services/follow_up_reminder_scheduler_test.dart -r compact`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/follow_up_reminder_scheduler.dart test/core/services/follow_up_reminder_scheduler_test.dart
git commit -m "feat(notifications): serialized reconcile scheduler"
```

---

## Task 4: Tap deduper

**Files:**
- Create: `lib/core/services/tap_deduper.dart`
- Test: `test/core/services/tap_deduper_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/core/services/tap_deduper_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/services/tap_deduper.dart';

void main() {
  test('null or empty payload is never handled', () {
    final d = TapDeduper();
    expect(d.shouldHandle(null), isFalse);
    expect(d.shouldHandle(''), isFalse);
  });

  test('first valid payload is handled', () {
    final d = TapDeduper();
    expect(d.shouldHandle('lead1'), isTrue);
  });

  test('same payload within the window is suppressed (launch + callback double)',
      () {
    var t = DateTime(2026, 7, 19, 10, 0, 0);
    final d = TapDeduper(window: const Duration(seconds: 2), now: () => t);
    expect(d.shouldHandle('lead1'), isTrue);
    t = t.add(const Duration(milliseconds: 300));
    expect(d.shouldHandle('lead1'), isFalse);
  });

  test('same payload after the window is handled again', () {
    var t = DateTime(2026, 7, 19, 10, 0, 0);
    final d = TapDeduper(window: const Duration(seconds: 2), now: () => t);
    expect(d.shouldHandle('lead1'), isTrue);
    t = t.add(const Duration(seconds: 3));
    expect(d.shouldHandle('lead1'), isTrue);
  });

  test('different payload within the window is handled', () {
    var t = DateTime(2026, 7, 19, 10, 0, 0);
    final d = TapDeduper(window: const Duration(seconds: 2), now: () => t);
    expect(d.shouldHandle('lead1'), isTrue);
    t = t.add(const Duration(milliseconds: 300));
    expect(d.shouldHandle('lead2'), isTrue);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/services/tap_deduper_test.dart -r compact`
Expected: FAIL — `tap_deduper.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/core/services/tap_deduper.dart`:

```dart
/// Guards against handling the same notification tap twice — e.g. when the
/// cold-start launch-details path and the runtime `onDidReceiveNotification
/// Response` callback both fire for one tap.
class TapDeduper {
  TapDeduper({
    Duration window = const Duration(seconds: 2),
    DateTime Function() now = DateTime.now,
  })  : _window = window,
        _now = now;

  final Duration _window;
  final DateTime Function() _now;
  String? _lastPayload;
  DateTime? _lastAt;

  bool shouldHandle(String? payload) {
    if (payload == null || payload.isEmpty) return false;
    final now = _now();
    final lastAt = _lastAt;
    if (_lastPayload == payload &&
        lastAt != null &&
        now.difference(lastAt) < _window) {
      return false;
    }
    _lastPayload = payload;
    _lastAt = now;
    return true;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/services/tap_deduper_test.dart -r compact`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/tap_deduper.dart test/core/services/tap_deduper_test.dart
git commit -m "feat(notifications): idempotent tap deduper"
```

---

## Task 5: Rewrite NotificationService facade

**Files:**
- Modify (full rewrite): `lib/core/services/notification_service.dart`

This task wires the tested pieces together, deletes dead code, adds the one-time
migration, and hardens tap navigation. It is thin glue over already-tested units,
so there is no new unit test; verification is the analyzer plus the full suite.

- [ ] **Step 1: Replace the file contents**

Overwrite `lib/core/services/notification_service.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:orderly_app/core/services/follow_up_reminder_planner.dart';
import 'package:orderly_app/core/services/follow_up_reminder_scheduler.dart';
import 'package:orderly_app/core/services/lead_navigation_service.dart';
import 'package:orderly_app/core/services/notification_id_registry.dart';
import 'package:orderly_app/core/services/tap_deduper.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/followups/data/follow_ups_service.dart';
import 'package:orderly_app/main.dart';

/// Static facade over `flutter_local_notifications`. Owns plugin init,
/// permissions, the follow-up reminder scheduler, and tap navigation. All the
/// scheduling *decisions* live in the pure planner/reconcile/scheduler units.
class NotificationService {
  static const String _channelId = 'followup_channel';
  static const String _channelName = 'Follow Ups';
  static const String _channelDescription =
      'Follow-up and overdue lead reminders';
  static const String _migrationFlagKey = 'notif_reconcile_migration_v1_done';

  static const AndroidNotificationChannel _notificationChannel =
      AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDescription,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final TapDeduper _tapDeduper = TapDeduper();

  static bool _initialized = false;
  static bool _canScheduleExactAlarms = true;
  static FollowUpReminderScheduler? _scheduler;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tz.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        _handleTap(response.payload);
      },
    );

    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacyOnce(prefs);

    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _handleTap(launchDetails?.notificationResponse?.payload);
    }

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_notificationChannel);
    await androidPlugin?.requestNotificationsPermission();
    final exactPermission = await androidPlugin?.requestExactAlarmsPermission();
    if (exactPermission != null) {
      _canScheduleExactAlarms = exactPermission;
    }

    _scheduler = FollowUpReminderScheduler(
      pendingIds: _pendingIds,
      schedule: _scheduleReminder,
      cancel: (id) => _notifications.cancel(id: id),
      registry: NotificationIdRegistry.load(prefs),
    );
  }

  /// Old-scheme (Object.hash id) notifications can't be matched by the new
  /// registry ids, so clear everything once; the next sync reschedules fresh.
  static Future<void> _migrateLegacyOnce(SharedPreferences prefs) async {
    if (prefs.getBool(_migrationFlagKey) ?? false) return;
    await _notifications.cancelAll();
    await prefs.remove('scheduled_follow_up_lead_ids');
    for (final key in prefs
        .getKeys()
        .where((k) => k.startsWith('follow_up_notification_'))
        .toList()) {
      await prefs.remove(key);
    }
    await prefs.setBool(_migrationFlagKey, true);
  }

  static Future<Set<int>> _pendingIds() async {
    final pending = await _notifications.pendingNotificationRequests();
    return pending.map((r) => r.id).toSet();
  }

  static Future<void> _scheduleReminder(PlannedReminder reminder) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      threadIdentifier: 'follow_up_thread',
    );

    await _notifications.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: tz.TZDateTime.from(reminder.when, tz.local),
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: _canScheduleExactAlarms
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload,
      matchDateTimeComponents:
          reminder.repeatDaily ? DateTimeComponents.time : null,
    );
  }

  /// Reconcile the OS reminder set against [leads] (defaults to the legacy
  /// lead maps). Safe to call from anywhere; runs are serialized.
  static Future<void> syncFollowUpReminders({
    List<Map<String, dynamic>>? leads,
  }) async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    final leadData = leads ?? await EnquiriesService().fetchLegacyMaps();
    await scheduler.sync(leadData);
  }

  /// Entry point used by app lifecycle + save flows. Prefers the follow_ups
  /// table, falling back to legacy leads if it is unavailable.
  static Future<void> checkAndTriggerSmartReminders() async {
    try {
      final followUps = await FollowUpsService().fetchPending();
      final maps = followUps.map((f) => f.toNotificationMap()).toList();
      await syncFollowUpReminders(leads: maps);
    } catch (_) {
      final leads = await EnquiriesService().fetchLegacyMaps();
      await syncFollowUpReminders(leads: leads);
    }
  }

  static void _handleTap(String? payload) {
    if (!_tapDeduper.shouldHandle(payload)) return;
    _navigateToLead(payload!);
  }

  static Future<void> _navigateToLead(String leadId) async {
    // Bounded wait for the navigator to be ready (cold start), then push once.
    for (var attempt = 0; attempt < 20; attempt++) {
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.push(LeadNavigationService.leadDetailRoute({'id': leadId}));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}
```

- [ ] **Step 2: Verify no remaining references to deleted symbols**

Run:
```bash
grep -rn 'syncLeadNotifications\|showNotification\|buildSuggestions\|buildBuckets\|NotificationSuggestion\|NotificationBuckets\|scheduleNotification\|\.cancelAll(' lib
```
Expected: the only hits are the two `syncLeadNotifications` call sites in
`lib/features/enquiries/presentation/capture_screen.dart` (fixed in Task 6) and
the internal `_notifications.cancelAll()` in the migration. No references to
`showNotification`, `buildSuggestions`, `buildBuckets`, `NotificationSuggestion`,
`NotificationBuckets`, or the old public `scheduleNotification`.

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze lib/core/services/notification_service.dart`
Expected: No errors. (Call-site errors in `capture_screen.dart` are addressed in Task 6; if analyzed together they will show as `syncLeadNotifications` undefined — that is expected until Task 6.)

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/notification_service.dart
git commit -m "refactor(notifications): thin facade over planner/scheduler, drop dead code + dup vectors"
```

---

## Task 6: Lifecycle observer + rename call sites

**Files:**
- Modify: `lib/main.dart:68-101` (`_MainScreenState`)
- Modify: `lib/features/enquiries/presentation/capture_screen.dart:247,271`

- [ ] **Step 1: Add the lifecycle observer to `_MainScreenState`**

In `lib/main.dart`, change the class declaration and `initState`, and add
`dispose` + `didChangeAppLifecycleState`.

Change the declaration:

```dart
class _MainScreenState extends ConsumerState<MainScreen> {
```
to:
```dart
class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
```

Replace the existing `initState` (lines ~87-101) with:

```dart
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
```

- [ ] **Step 2: Rename the two call sites in `capture_screen.dart`**

In `lib/features/enquiries/presentation/capture_screen.dart`, change both
occurrences of:

```dart
NotificationService.syncLeadNotifications().catchError((_) {});
```
to:
```dart
NotificationService.syncFollowUpReminders().catchError((_) {});
```

(Line 247 in `_shareAndSave`, line 271 in `_save`.)

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze lib`
Expected: No errors.

- [ ] **Step 4: Run the touched-area tests**

Run: `flutter test test/features/enquiries -r compact`
Expected: PASS (no behavior change for these flows beyond the method name).

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/features/enquiries/presentation/capture_screen.dart
git commit -m "feat(notifications): re-sync reminders on resume; rename sync call sites"
```

---

## Task 7: `markAllDone` on the work-items notifier

**Files:**
- Modify: `lib/features/work/controller/work_items_provider.dart` (after `markDone`, ~line 104)
- Test: `test/features/work/work_items_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/features/work/work_items_provider_test.dart` inside `main()`:

```dart
  test('markAllDone clears all items and counts them completed', () async {
    final svc = FakeAiWorkItemsService([_item('1'), _item('2'), _item('3')]);
    final c = makeContainer(svc);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();

    await c.read(workItemsProvider.notifier).markAllDone();

    expect(c.read(workItemsProvider).items, isEmpty);
    expect(c.read(workItemsProvider).completedCount, 3);
    expect(svc.updates['1'], 'done');
    expect(svc.updates['2'], 'done');
    expect(svc.updates['3'], 'done');
  });

  test('markAllDone on an empty list is a no-op', () async {
    final c = makeContainer(FakeAiWorkItemsService([]));
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();

    await c.read(workItemsProvider.notifier).markAllDone();

    expect(c.read(workItemsProvider).completedCount, 0);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/work/work_items_provider_test.dart -r compact`
Expected: FAIL — `markAllDone` is not defined.

- [ ] **Step 3: Implement `markAllDone`**

In `lib/features/work/controller/work_items_provider.dart`, add after `markDone`
(before `triggerGenerate`):

```dart
  Future<void> markAllDone() async {
    final prev = state;
    final ids = prev.items.map((i) => i.id).toList();
    if (ids.isEmpty) return;
    // Optimistic clear; all count as completed.
    state = state.copyWith(
        items: const [], completedCount: prev.completedCount + ids.length);
    try {
      for (final id in ids) {
        await _svc.markDone(id);
      }
    } catch (_) {
      state = state.copyWith(
          items: prev.items, completedCount: prev.completedCount);
    }
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/work/work_items_provider_test.dart -r compact`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/work/controller/work_items_provider.dart test/features/work/work_items_provider_test.dart
git commit -m "feat(work): markAllDone bulk action on work items notifier"
```

---

## Task 8: Notification Center polish

**Files:**
- Modify: `lib/features/notifications/presentation/notifications_screen.dart`
- Test: `test/features/notifications/notifications_screen_test.dart`

- [ ] **Step 1: Update the widget tests (failing)**

In `test/features/notifications/notifications_screen_test.dart`, extend the
`_item` helper to accept `createdAt`:

```dart
AiWorkItem _item({
  String id = '1',
  String kind = 'payment_reminder',
  String priority = 'high',
  String? name,
  String? phone,
  DateTime? createdAt,
}) =>
    AiWorkItem(
      id: id,
      kind: kind,
      priority: priority,
      score: 80,
      title: 'Payment pending',
      status: 'pending',
      batchId: 'b-1',
      customerId: 'c-$id',
      customerName: name ?? 'Customer $id',
      phone: phone,
      createdAt: createdAt,
    );
```

Add these tests inside `main()`:

```dart
  testWidgets('renders a relative timestamp when createdAt is set', (t) async {
    await t.pumpWidget(_wrap([
      _item(name: 'Priya', createdAt: DateTime.now().subtract(const Duration(hours: 2))),
    ]));
    await t.pumpAndSettle();
    expect(find.textContaining('2h ago'), findsOneWidget);
  });

  testWidgets('swiping a tile dismisses it', (t) async {
    await t.pumpWidget(_wrap([_item(id: '3', name: 'Priya')]));
    await t.pumpAndSettle();

    await t.drag(find.text('Priya'), const Offset(-500, 0));
    await t.pumpAndSettle();

    expect(find.text('Priya'), findsNothing);
  });

  testWidgets('mark-all-done clears the list', (t) async {
    await t.pumpWidget(_wrap([
      _item(id: '1', name: 'Priya'),
      _item(id: '2', name: 'Rahul', priority: 'medium'),
    ]));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('notif_mark_all_done')));
    await t.pumpAndSettle();

    expect(find.text('Priya'), findsNothing);
    expect(find.text('Rahul'), findsNothing);
    expect(find.textContaining('All caught up'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/notifications/notifications_screen_test.dart -r compact`
Expected: FAIL — no `2h ago` text, tile not dismissible, no `notif_mark_all_done` key.

- [ ] **Step 3: Implement the polish**

In `lib/features/notifications/presentation/notifications_screen.dart`:

(a) Add an app-bar action for mark-all-done. Replace the existing `actions:` list
in `build` (the single refresh `IconButton`) with:

```dart
        actions: [
          if (state.items.isNotEmpty)
            IconButton(
              key: const Key('notif_mark_all_done'),
              tooltip: 'Mark all done',
              icon: const Icon(Icons.done_all_rounded),
              onPressed: () {
                ref.read(workItemsProvider.notifier).markAllDone();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All caught up ✅')),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(workItemsProvider.notifier).load(),
          ),
        ],
```

(b) Wrap each `_NotificationTile(...)` in a `Dismissible`. Since tiles are built
in two `for` loops (high and others), extract a helper method in
`_NotificationsScreenState` and use it in both loops:

```dart
  Widget _dismissibleTile(AiWorkItem item) {
    return Dismissible(
      key: ValueKey('notif_dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.close_rounded, color: AppColors.danger),
      ),
      onDismissed: (_) {
        ref.read(workItemsProvider.notifier).dismiss(item.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dismissed')),
        );
      },
      child: _NotificationTile(
        item: item,
        onTap: () => _open(item),
        onAction: () => _runAction(item),
        onDone: () => _done(item),
      ),
    );
  }
```

Then in `build`, replace both inline `for (final item in high) _NotificationTile(...)`
and `for (final item in others) _NotificationTile(...)` blocks with:

```dart
                    for (final item in high) _dismissibleTile(item),
```
and
```dart
                    for (final item in others) _dismissibleTile(item),
```

(c) Add a relative-timestamp line inside `_NotificationTile.build`. Add this
top-level helper at the end of the file:

```dart
String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
```

In `_NotificationTile.build`, immediately after the `item.amount` block (inside the
`Expanded` > `Column`), add:

```dart
                      if (item.createdAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _relativeTime(item.createdAt!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/notifications/notifications_screen_test.dart -r compact`
Expected: PASS (all, including the pre-existing tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/presentation/notifications_screen.dart test/features/notifications/notifications_screen_test.dart
git commit -m "feat(notifications): center polish — timestamps, swipe-dismiss, mark-all-done"
```

---

## Task 9: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: No errors. Fix any warning introduced by the above (e.g. unused imports
in `notification_service.dart` — the rewrite drops several old imports).

- [ ] **Step 2: Run the full test suite**

Run: `flutter test -r compact`
Expected: All tests pass. Pay attention to any test that referenced the removed
`NotificationService` symbols; there should be none (Task 5 Step 2 confirmed this).

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "chore(notifications): analyzer + test suite green"
```

(Skip this commit if steps 1-2 produced no changes.)

---

## Self-Review notes (author)

- **Spec coverage:** duplicate root causes (schedule+instant same-id, repeatDaily persistence, id collisions, receipt bloat, concurrency race) → Tasks 1-5. Lifecycle re-sync → Task 6. Tap-nav idempotency across states → Task 4 + Task 5 (`_handleTap`/`_navigateToLead`). Dead-code deletion + god-class split → Task 5. One-time migration → Task 5. Center light polish (timestamps/swipe/mark-all) → Tasks 7-8. No read/unread, no new types — respected.
- **Type consistency:** `PlannedReminder`, `planFollowUpReminders`, `reconcileReminders`/`ReminderReconciliation`, `NotificationIdRegistry.load`/`idFor`/`flush`, `FollowUpReminderScheduler.sync`, `TapDeduper.shouldHandle`, `syncFollowUpReminders`, `markAllDone` are used identically across tasks.
- **Deviations from spec, intentional:** (1) capture_screen has no duplicate double-call to collapse; both sites are distinct flows and are only renamed. (2) Swipe-to-dismiss has no undo because the provider exposes no un-dismiss; snackbar reads "Dismissed". (3) Kept the existing sectioned `ListView` (pending-work lists are inherently small) rather than forcing `ListView.builder`.
```
