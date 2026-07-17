# Start My Work — Focus Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full-screen, guided "Focus Mode" that walks a Closr owner through today's pending AI work items one task at a time, launched from the existing `Start My Work →` CTA.

**Architecture:** New `lib/features/focus/` module. Pure Dart logic in `data/` (session queue, copy, persistence, action mapping) is unit-tested with no Flutter/I/O. A Riverpod `StateNotifier` layers over the existing `workItemsProvider` so completions mutate the same `ai_work_items` and sync to Home + My Work for free. Presentation is a pushed full-screen route (nav shell untouched); each screen is a pure function of session state. Pixel-exact visuals follow the approved mockup at `.superpowers/brainstorm/22472-1784284202/content/focus-mode-full.html`.

**Tech Stack:** Flutter, flutter_riverpod, shared_preferences, url_launcher, flutter_test.

**Spec:** `docs/superpowers/specs/2026-07-17-start-my-work-focus-mode-design.md`

**Commands:** test a file → `flutter test <path>`; static check → `flutter analyze lib/features/focus`.

---

## File Structure

**Create:**
- `lib/features/work/data/work_item_kinds.dart` — public kind predicates + group enum (shared).
- `lib/features/focus/data/focus_session.dart` — `FocusSession`, `FocusSummary` (pure).
- `lib/features/focus/data/focus_copy.dart` — deterministic AI copy (pure).
- `lib/features/focus/data/focus_action.dart` — `FocusActionKind`, `resolveFocusAction` (pure).
- `lib/features/focus/data/focus_snapshot.dart` — serialisable session snapshot + resume rule (pure).
- `lib/features/focus/data/focus_session_store.dart` — `SharedPreferences` persistence.
- `lib/features/focus/controller/focus_session_provider.dart` — `FocusModeState` + notifier.
- `lib/features/focus/presentation/orbit.dart` — mascot widget.
- `lib/features/focus/presentation/focus_task_card.dart` — kind-driven task template.
- `lib/features/focus/presentation/focus_screens.dart` — entry / resume / empty / success / finish.
- `lib/features/focus/presentation/focus_overlays.dart` — skip sheet, exit dialog, error toast.
- `lib/features/focus/presentation/focus_mode_route.dart` — full-screen route + branching + `FocusMode.start`.

**Modify:**
- `lib/features/today/data/brief_narrative.dart` — delegate private predicates to shared file.
- `lib/features/today/presentation/today_screen.dart:851` — CTA calls `FocusMode.start`.
- `lib/features/work/presentation/my_work_screen.dart` — add `Start My Work` entry affordance.

**Test:** mirror under `test/features/focus/` and `test/features/work/`.

---

### Task 1: Shared work-item kind predicates

**Files:**
- Create: `lib/features/work/data/work_item_kinds.dart`
- Modify: `lib/features/today/data/brief_narrative.dart:34-40`
- Test: `test/features/work/work_item_kinds_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/work/work_item_kinds_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/work/data/work_item_kinds.dart';

void main() {
  test('classifies kinds into groups', () {
    expect(workItemGroup('payment_reminder'), WorkItemGroup.collect);
    expect(workItemGroup('overdue_payment'), WorkItemGroup.collect);
    expect(workItemGroup('reply'), WorkItemGroup.reply);
    expect(workItemGroup('follow_up'), WorkItemGroup.reply);
    expect(workItemGroup('call'), WorkItemGroup.reply);
    expect(workItemGroup('share_catalog'), WorkItemGroup.offer);
    expect(workItemGroup('offer'), WorkItemGroup.offer);
    expect(workItemGroup('something_new'), WorkItemGroup.other);
  });

  test('predicates match groups', () {
    expect(isCollectKind('overdue_payment'), isTrue);
    expect(isReplyKind('call'), isTrue);
    expect(isOfferKind('offer'), isTrue);
    expect(isCollectKind('reply'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/work/work_item_kinds_test.dart`
Expected: FAIL — `work_item_kinds.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/work/data/work_item_kinds.dart

/// Coarse grouping of AI work-item kinds, shared by the Home brief and Focus Mode.
enum WorkItemGroup { collect, reply, offer, other }

bool isCollectKind(String kind) =>
    kind == 'payment_reminder' || kind == 'overdue_payment';

bool isReplyKind(String kind) =>
    kind == 'follow_up' || kind == 'call' || kind == 'reply';

bool isOfferKind(String kind) => kind == 'share_catalog' || kind == 'offer';

WorkItemGroup workItemGroup(String kind) {
  if (isCollectKind(kind)) return WorkItemGroup.collect;
  if (isReplyKind(kind)) return WorkItemGroup.reply;
  if (isOfferKind(kind)) return WorkItemGroup.offer;
  return WorkItemGroup.other;
}
```

- [ ] **Step 4: Delegate the private predicates in brief_narrative.dart**

Replace `brief_narrative.dart:34-40` with delegating wrappers (keeps existing tests green):

```dart
bool _isCollectKind(String kind) => isCollectKind(kind);
bool _isReplyKind(String kind) => isReplyKind(kind);
bool _isOfferKind(String kind) => isOfferKind(kind);
```

Add the import at the top of `brief_narrative.dart`:

```dart
import 'package:orderly_app/features/work/data/work_item_kinds.dart';
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/work/work_item_kinds_test.dart test/features/today/brief_narrative_test.dart`
Expected: PASS (both the new test and the untouched brief tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/work/data/work_item_kinds.dart lib/features/today/data/brief_narrative.dart test/features/work/work_item_kinds_test.dart
git commit -m "refactor(work): extract shared work-item kind predicates"
```

---

### Task 2: FocusSession — start, current, progress

**Files:**
- Create: `lib/features/focus/data/focus_session.dart`
- Test: `test/features/focus/focus_session_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_session_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_session.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _item(String id, {String kind = 'payment_reminder', int score = 0, double? amount}) =>
    AiWorkItem(
      id: id, kind: kind, priority: 'high', score: score, title: 't',
      status: 'pending', batchId: 'b1', amount: amount,
    );

void main() {
  final now = DateTime(2026, 7, 17, 9);

  test('start freezes total and orders by score desc', () {
    final s = FocusSession.start(
      [_item('a', score: 1), _item('b', score: 5), _item('c', score: 3)],
      now: now, batchId: 'b1',
    );
    expect(s.sessionTotal, 3);
    expect(s.queue.map((i) => i.id).toList(), ['b', 'c', 'a']);
    expect(s.current!.id, 'b');
    expect(s.completedCount, 0);
    expect(s.progress, 0);
    expect(s.position, 1);
    expect(s.isEmpty, isFalse);
    expect(s.isFinished, isFalse);
  });

  test('empty session', () {
    final s = FocusSession.start([], now: now, batchId: 'b1');
    expect(s.isEmpty, isTrue);
    expect(s.current, isNull);
    expect(s.progress, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_session_test.dart`
Expected: FAIL — `focus_session.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/focus/data/focus_session.dart
import 'package:orderly_app/features/work/data/ai_work_item.dart';

/// Immutable snapshot of a guided Focus Mode run. Pure — no Flutter, no I/O.
class FocusSession {
  const FocusSession({
    required this.queue,
    required this.completed,
    required this.skippedIds,
    required this.sessionTotal,
    required this.startedAt,
    required this.batchId,
  });

  /// Not-yet-done items, current task first. Skips move to the tail.
  final List<AiWorkItem> queue;

  /// Items finished this session, in completion order.
  final List<AiWorkItem> completed;

  /// Ids skipped at least once (a task may be skipped only once).
  final Set<String> skippedIds;

  /// Denominator for progress — frozen at start so it never shifts.
  final int sessionTotal;
  final DateTime startedAt;
  final String batchId;

  factory FocusSession.start(
    List<AiWorkItem> pending, {
    required DateTime now,
    required String batchId,
  }) {
    final ordered = [...pending]..sort((a, b) => b.score.compareTo(a.score));
    return FocusSession(
      queue: ordered,
      completed: const [],
      skippedIds: const {},
      sessionTotal: ordered.length,
      startedAt: now,
      batchId: batchId,
    );
  }

  AiWorkItem? get current => queue.isEmpty ? null : queue.first;
  int get completedCount => completed.length;
  double get progress => sessionTotal == 0 ? 0 : completedCount / sessionTotal;

  /// 1-based index of the current task within the frozen total.
  int get position => completedCount + 1;
  bool get isEmpty => sessionTotal == 0;
  bool get isFinished => sessionTotal > 0 && queue.isEmpty;

  FocusSession copyWith({
    List<AiWorkItem>? queue,
    List<AiWorkItem>? completed,
    Set<String>? skippedIds,
  }) =>
      FocusSession(
        queue: queue ?? this.queue,
        completed: completed ?? this.completed,
        skippedIds: skippedIds ?? this.skippedIds,
        sessionTotal: sessionTotal,
        startedAt: startedAt,
        batchId: batchId,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/data/focus_session.dart test/features/focus/focus_session_test.dart
git commit -m "feat(focus): add FocusSession start/progress model"
```

---

### Task 3: FocusSession — complete, skip (skip-once), remaining minutes

**Files:**
- Modify: `lib/features/focus/data/focus_session.dart`
- Test: `test/features/focus/focus_session_test.dart`

- [ ] **Step 1: Add failing tests**

```dart
  test('complete moves current to completed and advances', () {
    var s = FocusSession.start(
      [_item('a', score: 3), _item('b', score: 2)], now: now, batchId: 'b1');
    s = s.complete();
    expect(s.completedCount, 1);
    expect(s.current!.id, 'b');
    expect(s.progress, 0.5);
    expect(s.position, 2);
    s = s.complete();
    expect(s.isFinished, isTrue);
    expect(s.current, isNull);
    expect(s.progress, 1);
  });

  test('skip requeues current to tail and can only skip once', () {
    var s = FocusSession.start(
      [_item('a', score: 3), _item('b', score: 2)], now: now, batchId: 'b1');
    expect(s.canSkip, isTrue);
    s = s.skip();
    expect(s.current!.id, 'b');
    expect(s.queue.map((i) => i.id).toList(), ['b', 'a']);
    expect(s.skippedIds, contains('a'));
    s = s.complete(); // finish b
    expect(s.current!.id, 'a');
    expect(s.canSkip, isFalse); // already skipped + last item
  });

  test('remaining minutes sums per-kind estimate over the queue', () {
    final s = FocusSession.start(
      [_item('a', kind: 'payment_reminder'), _item('b', kind: 'reply')],
      now: now, batchId: 'b1'); // 2 + 3
    expect(s.remainingMinutes, 5);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_session_test.dart`
Expected: FAIL — `complete`, `skip`, `canSkip`, `remainingMinutes` undefined.

- [ ] **Step 3: Implement**

Add the import and members to `focus_session.dart`:

```dart
import 'package:orderly_app/features/today/data/brief_narrative.dart'
    show estimatedMinutesFor;
```

```dart
  /// A task can be skipped only if it is not the last one and has not been
  /// skipped before — so a skipped task always resurfaces and must be handled.
  bool get canSkip =>
      queue.length > 1 && current != null && !skippedIds.contains(current!.id);

  int get remainingMinutes =>
      queue.fold(0, (sum, i) => sum + estimatedMinutesFor(i));

  FocusSession complete() {
    if (current == null) return this;
    return copyWith(
      queue: queue.sublist(1),
      completed: [...completed, current!],
    );
  }

  FocusSession skip() {
    if (!canSkip) return this;
    final head = queue.first;
    return copyWith(
      queue: [...queue.sublist(1), head],
      skippedIds: {...skippedIds, head.id},
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/data/focus_session.dart test/features/focus/focus_session_test.dart
git commit -m "feat(focus): add complete/skip/remaining-minutes to FocusSession"
```

---

### Task 4: FocusSummary — finish-screen tallies

**Files:**
- Modify: `lib/features/focus/data/focus_session.dart`
- Test: `test/features/focus/focus_summary_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_summary_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_session.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _i(String id, String kind, {double? amount}) => AiWorkItem(
    id: id, kind: kind, priority: 'high', score: 0, title: 't',
    status: 'pending', batchId: 'b1', amount: amount);

void main() {
  test('summary tallies completed items by group', () {
    var s = FocusSession.start([
      _i('a', 'overdue_payment', amount: 8597),
      _i('b', 'payment_reminder', amount: 10803),
      _i('c', 'reply'),
      _i('d', 'follow_up'),
      _i('e', 'offer'),
    ], now: DateTime(2026, 7, 17), batchId: 'b1');
    for (var k = 0; k < 5; k++) {
      s = s.complete();
    }
    final sum = s.summary();
    expect(sum.tasksCompleted, 5);
    expect(sum.paymentsFollowedUp, 2);
    expect(sum.amountFollowedUp, 19400);
    expect(sum.repliesSent, 2);
    expect(sum.offersSent, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_summary_test.dart`
Expected: FAIL — `summary`/`FocusSummary` undefined.

- [ ] **Step 3: Implement**

Add to `focus_session.dart` (import the shared groups at top):

```dart
import 'package:orderly_app/features/work/data/work_item_kinds.dart';
```

```dart
  FocusSummary summary() {
    var payments = 0, replies = 0, offers = 0;
    var amount = 0.0;
    for (final i in completed) {
      switch (workItemGroup(i.kind)) {
        case WorkItemGroup.collect:
          payments++;
          amount += i.amount ?? 0;
        case WorkItemGroup.reply:
          replies++;
        case WorkItemGroup.offer:
          offers++;
        case WorkItemGroup.other:
          break;
      }
    }
    return FocusSummary(
      tasksCompleted: completed.length,
      paymentsFollowedUp: payments,
      amountFollowedUp: (amount * 100).round() / 100,
      repliesSent: replies,
      offersSent: offers,
    );
  }
}

/// Immutable tally shown on the finish screen.
class FocusSummary {
  const FocusSummary({
    required this.tasksCompleted,
    required this.paymentsFollowedUp,
    required this.amountFollowedUp,
    required this.repliesSent,
    required this.offersSent,
  });
  final int tasksCompleted;
  final int paymentsFollowedUp;
  final double amountFollowedUp;
  final int repliesSent;
  final int offersSent;
}
```

Note: the `}` above closes `class FocusSession`; place `summary()` inside it and `FocusSummary` after it.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_summary_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/data/focus_session.dart test/features/focus/focus_summary_test.dart
git commit -m "feat(focus): add FocusSummary tallies"
```

---

### Task 5: Deterministic AI copy

**Files:**
- Create: `lib/features/focus/data/focus_copy.dart`
- Test: `test/features/focus/focus_copy_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_copy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_copy.dart';

int _words(String s) => s.trim().split(RegExp(r'\s+')).length;

void main() {
  test('entry line mentions task count and stays short', () {
    final line = focusEntryLine(5);
    expect(line, contains('5'));
    expect(_words(line), lessThanOrEqualTo(10));
  });

  test('task lead differs by group and stays short', () {
    expect(focusTaskLead('overdue_payment', 'Aman'), contains('payment'));
    expect(focusTaskLead('reply', 'Meera'), contains('Meera'));
    expect(_words(focusTaskLead('offer', 'Karan')), lessThanOrEqualTo(8));
  });

  test('success line reflects remaining', () {
    expect(focusSuccessLine(3), contains('3'));
    expect(_words(focusSuccessLine(1)), lessThanOrEqualTo(8));
  });

  test('finish line greets by name', () {
    expect(focusFinishLine('Rahul'), contains('Rahul'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_copy_test.dart`
Expected: FAIL — `focus_copy.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/focus/data/focus_copy.dart
import 'package:orderly_app/features/work/data/work_item_kinds.dart';

/// Deterministic, one-line assistant copy. No free-form generation — every
/// string is derived from position/kind so it is testable and never chatty.

String focusEntryLine(int taskCount) =>
    "Let's clear your $taskCount tasks together.";

String focusTaskLead(String kind, String firstName) {
  switch (workItemGroup(kind)) {
    case WorkItemGroup.collect:
      return "Let's start with this payment.";
    case WorkItemGroup.reply:
      return "$firstName's waiting — let's reply.";
    case WorkItemGroup.offer:
      return "Let's win $firstName back.";
    case WorkItemGroup.other:
      return "Let's handle this next.";
  }
}

String focusSuccessLine(int remaining) => remaining == 1
    ? 'Nice work! Just 1 more to go.'
    : 'Nice work! $remaining more to go.';

String focusFinishLine(String firstName) => 'Great momentum today, $firstName.';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_copy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/data/focus_copy.dart test/features/focus/focus_copy_test.dart
git commit -m "feat(focus): add deterministic assistant copy"
```

---

### Task 6: Primary action resolver

**Files:**
- Create: `lib/features/focus/data/focus_action.dart`
- Test: `test/features/focus/focus_action_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_action_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_action.dart';

void main() {
  test('maps kind groups to a primary action', () {
    expect(resolveFocusAction('overdue_payment'), FocusActionKind.sendReminder);
    expect(resolveFocusAction('payment_reminder'), FocusActionKind.sendReminder);
    expect(resolveFocusAction('reply'), FocusActionKind.sendReply);
    expect(resolveFocusAction('follow_up'), FocusActionKind.sendReply);
    expect(resolveFocusAction('offer'), FocusActionKind.sendOffer);
    expect(resolveFocusAction('mystery'), FocusActionKind.openWorkspace);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_action_test.dart`
Expected: FAIL — `focus_action.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/focus/data/focus_action.dart
import 'package:orderly_app/features/work/data/work_item_kinds.dart';

/// The primary action a Focus task offers. Presentation maps each to a label,
/// icon, colour and handler; the mapping *by kind* lives here so it is testable.
enum FocusActionKind { sendReminder, sendReply, sendOffer, openWorkspace }

FocusActionKind resolveFocusAction(String kind) {
  switch (workItemGroup(kind)) {
    case WorkItemGroup.collect:
      return FocusActionKind.sendReminder;
    case WorkItemGroup.reply:
      return FocusActionKind.sendReply;
    case WorkItemGroup.offer:
      return FocusActionKind.sendOffer;
    case WorkItemGroup.other:
      return FocusActionKind.openWorkspace;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_action_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/data/focus_action.dart test/features/focus/focus_action_test.dart
git commit -m "feat(focus): add primary action resolver"
```

---

### Task 7: Session snapshot + resume rule (pure)

**Files:**
- Create: `lib/features/focus/data/focus_snapshot.dart`
- Test: `test/features/focus/focus_snapshot_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_snapshot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_snapshot.dart';

void main() {
  final snap = FocusSnapshot(
    batchId: 'b1',
    orderedIds: const ['a', 'b'],
    completedIds: const ['x', 'y', 'z'],
    skippedIds: const ['a'],
    sessionTotal: 5,
    startedAt: DateTime(2026, 7, 17, 9),
  );

  test('round-trips through JSON', () {
    final back = FocusSnapshot.fromJson(snap.toJson());
    expect(back.batchId, 'b1');
    expect(back.orderedIds, ['a', 'b']);
    expect(back.completedIds, ['x', 'y', 'z']);
    expect(back.skippedIds, ['a']);
    expect(back.sessionTotal, 5);
    expect(back.startedAt, DateTime(2026, 7, 17, 9));
  });

  test('resumable only when batch matches, same day, and work remains', () {
    final now = DateTime(2026, 7, 17, 14);
    expect(snap.isResumable(currentBatchId: 'b1', now: now), isTrue);
    expect(snap.isResumable(currentBatchId: 'b2', now: now), isFalse);
    expect(snap.isResumable(currentBatchId: 'b1', now: DateTime(2026, 7, 18, 9)),
        isFalse);
    final done = FocusSnapshot(
      batchId: 'b1', orderedIds: const [], completedIds: const ['x'],
      skippedIds: const [], sessionTotal: 1, startedAt: DateTime(2026, 7, 17));
    expect(done.isResumable(currentBatchId: 'b1', now: now), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_snapshot_test.dart`
Expected: FAIL — `focus_snapshot.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/focus/data/focus_snapshot.dart

/// Serialisable view of an in-progress session, persisted for resume.
class FocusSnapshot {
  const FocusSnapshot({
    required this.batchId,
    required this.orderedIds,
    required this.completedIds,
    required this.skippedIds,
    required this.sessionTotal,
    required this.startedAt,
  });

  final String batchId;
  final List<String> orderedIds;
  final List<String> completedIds;
  final List<String> skippedIds;
  final int sessionTotal;
  final DateTime startedAt;

  int get remaining => orderedIds.length;

  bool isResumable({required String currentBatchId, required DateTime now}) =>
      batchId == currentBatchId &&
      remaining > 0 &&
      startedAt.year == now.year &&
      startedAt.month == now.month &&
      startedAt.day == now.day;

  Map<String, dynamic> toJson() => {
        'batchId': batchId,
        'orderedIds': orderedIds,
        'completedIds': completedIds,
        'skippedIds': skippedIds,
        'sessionTotal': sessionTotal,
        'startedAt': startedAt.toIso8601String(),
      };

  factory FocusSnapshot.fromJson(Map<String, dynamic> json) => FocusSnapshot(
        batchId: json['batchId'] as String,
        orderedIds: (json['orderedIds'] as List).cast<String>(),
        completedIds: (json['completedIds'] as List).cast<String>(),
        skippedIds: (json['skippedIds'] as List).cast<String>(),
        sessionTotal: json['sessionTotal'] as int,
        startedAt: DateTime.parse(json['startedAt'] as String),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_snapshot_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/data/focus_snapshot.dart test/features/focus/focus_snapshot_test.dart
git commit -m "feat(focus): add session snapshot and resume rule"
```

---

### Task 8: SharedPreferences session store

**Files:**
- Create: `lib/features/focus/data/focus_session_store.dart`
- Test: `test/features/focus/focus_session_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_session_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orderly_app/features/focus/data/focus_session_store.dart';
import 'package:orderly_app/features/focus/data/focus_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('save, read, clear round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FocusSessionStore(await SharedPreferences.getInstance());
    expect(await store.read(), isNull);

    final snap = FocusSnapshot(
      batchId: 'b1', orderedIds: const ['a'], completedIds: const ['x'],
      skippedIds: const [], sessionTotal: 2, startedAt: DateTime(2026, 7, 17));
    await store.save(snap);

    final back = await store.read();
    expect(back!.batchId, 'b1');
    expect(back.orderedIds, ['a']);

    await store.clear();
    expect(await store.read(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_session_store_test.dart`
Expected: FAIL — `focus_session_store.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/focus/data/focus_session_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'focus_snapshot.dart';

/// Persists the active Focus session so it can be resumed after leaving.
class FocusSessionStore {
  FocusSessionStore(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'focus_session_v1';

  Future<void> save(FocusSnapshot snapshot) async {
    await _prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<FocusSnapshot?> read() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return FocusSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> clear() async => _prefs.remove(_key);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_session_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/data/focus_session_store.dart test/features/focus/focus_session_store_test.dart
git commit -m "feat(focus): add SharedPreferences session store"
```

---

### Task 9: Focus session provider (state + mutations + sync)

**Files:**
- Create: `lib/features/focus/controller/focus_session_provider.dart`
- Test: `test/features/focus/focus_session_provider_test.dart`

The provider layers over `workItemsProvider`; completing a task calls the existing
`approve`/`markDone`, which is what makes Focus completions sync to Home + My Work.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_session_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/focus/controller/focus_session_provider.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';
import 'package:orderly_app/features/work/data/ai_work_items_service.dart';

class _FakeSvc implements AiWorkItemsService {
  _FakeSvc(this._items);
  List<AiWorkItem> _items;
  final approved = <String>[];
  @override
  Future<List<AiWorkItem>> fetchPending() async => _items;
  @override
  Future<void> approve(String id) async => approved.add(id);
  @override
  Future<void> markDone(String id) async => approved.add(id);
  @override
  Future<void> dismiss(String id) async {}
  @override
  Future<void> updateStatus(String id, String s) async {}
  @override
  Future<void> triggerGenerate() async {}
}

AiWorkItem _i(String id, int score) => AiWorkItem(
    id: id, kind: 'payment_reminder', priority: 'high', score: score,
    title: 't', status: 'pending', batchId: 'b1');

void main() {
  test('start builds a session from pending work items', () async {
    final svc = _FakeSvc([_i('a', 1), _i('b', 2)]);
    final c = ProviderContainer(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);

    await c.read(workItemsProvider.notifier).load();
    await c.read(focusSessionProvider.notifier).start(now: DateTime(2026, 7, 17));

    final state = c.read(focusSessionProvider);
    expect(state.status, FocusStatus.active);
    expect(state.session!.sessionTotal, 2);
    expect(state.session!.current!.id, 'b');
  });

  test('completeCurrent approves via work items and advances', () async {
    final svc = _FakeSvc([_i('a', 2)]);
    final c = ProviderContainer(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);

    await c.read(workItemsProvider.notifier).load();
    await c.read(focusSessionProvider.notifier).start(now: DateTime(2026, 7, 17));
    await c.read(focusSessionProvider.notifier).completeCurrent();

    expect(svc.approved, ['a']); // synced to server/other screens
    expect(c.read(focusSessionProvider).status, FocusStatus.celebrating);
    expect(c.read(focusSessionProvider).session!.isFinished, isTrue);
  });

  test('empty pending yields empty status', () async {
    final svc = _FakeSvc([]);
    final c = ProviderContainer(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);
    await c.read(workItemsProvider.notifier).load();
    await c.read(focusSessionProvider.notifier).start(now: DateTime(2026, 7, 17));
    expect(c.read(focusSessionProvider).status, FocusStatus.empty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_session_provider_test.dart`
Expected: FAIL — provider does not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/focus/controller/focus_session_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/focus_session.dart';
import '../../work/controller/work_items_provider.dart';

enum FocusStatus { entry, resume, active, celebrating, finished, empty }

class FocusModeState {
  const FocusModeState({
    this.session,
    this.status = FocusStatus.entry,
    this.sending = false,
    this.actionError,
  });

  final FocusSession? session;
  final FocusStatus status;
  final bool sending;
  final String? actionError;

  FocusModeState copyWith({
    FocusSession? session,
    FocusStatus? status,
    bool? sending,
    String? Function()? actionError,
  }) =>
      FocusModeState(
        session: session ?? this.session,
        status: status ?? this.status,
        sending: sending ?? this.sending,
        actionError: actionError != null ? actionError() : this.actionError,
      );
}

class FocusSessionNotifier extends StateNotifier<FocusModeState> {
  FocusSessionNotifier(this._ref) : super(const FocusModeState());
  final Ref _ref;

  Future<void> start({required DateTime now}) async {
    final items = _ref.read(workItemsProvider).items;
    if (items.isEmpty) {
      state = const FocusModeState(status: FocusStatus.empty);
      return;
    }
    final batchId = items.first.batchId;
    final session = FocusSession.start(items, now: now, batchId: batchId);
    state = FocusModeState(session: session, status: FocusStatus.active);
  }

  Future<void> completeCurrent({bool markDone = false}) async {
    final s = state.session;
    if (s?.current == null) return;
    final id = s!.current!.id;
    state = state.copyWith(sending: true, actionError: () => null);
    try {
      final work = _ref.read(workItemsProvider.notifier);
      markDone ? await work.markDone(id) : await work.approve(id);
      state = state.copyWith(
        session: s.complete(), status: FocusStatus.celebrating, sending: false);
    } catch (e) {
      state = state.copyWith(sending: false, actionError: () => e.toString());
    }
  }

  /// Called by the UI after the success animation to reveal the next task.
  void advance() {
    final s = state.session;
    if (s == null) return;
    state = state.copyWith(
      status: s.isFinished ? FocusStatus.finished : FocusStatus.active);
  }

  void skipCurrent() {
    final s = state.session;
    if (s == null) return;
    state = state.copyWith(session: s.skip(), status: FocusStatus.active);
  }

  void clearError() => state = state.copyWith(actionError: () => null);
}

final focusSessionProvider =
    StateNotifierProvider<FocusSessionNotifier, FocusModeState>(
  (ref) => FocusSessionNotifier(ref),
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_session_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/controller/focus_session_provider.dart test/features/focus/focus_session_provider_test.dart
git commit -m "feat(focus): add session provider with work-items sync"
```

**Note on persistence wiring:** `FocusSessionStore` save/read is integrated in Task 13 (route), where a `SharedPreferences` instance is available. The provider stays free of I/O so it is trivially testable; the route calls `store.save(...)` after each `completeCurrent`/`skipCurrent` and `store.clear()` on finish. Resume branching uses `FocusSnapshot.isResumable` (Task 7).

---

### Task 10: Orbit mascot widget

**Files:**
- Create: `lib/features/focus/presentation/orbit.dart`
- Test: `test/features/focus/orbit_test.dart`

Visual reference: the four Orbit expressions in `.superpowers/brainstorm/22472-1784284202/content/orbit-expressions.html` (neutral / thinking / happy / celebrating). Build as a `CustomPaint` (or grouped shapes) driven by `OrbitMood`; idle bob + blink via an `AnimationController`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/orbit_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/orbit.dart';

void main() {
  testWidgets('renders each mood without error', (tester) async {
    for (final mood in OrbitMood.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: Orbit(mood: mood, size: 96)))));
      expect(find.byType(Orbit), findsOneWidget);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/orbit_test.dart`
Expected: FAIL — `orbit.dart` does not exist.

- [ ] **Step 3: Implement**

Create `Orbit` (a `StatefulWidget` with `SingleTickerProviderStateMixin` for the bob/blink loop) exposing:

```dart
enum OrbitMood { neutral, thinking, happy, celebrating }

class Orbit extends StatefulWidget {
  const Orbit({super.key, required this.mood, this.size = 120});
  final OrbitMood mood;
  final double size;
  // ...
}
```

Render the capsule body, dark visor, mood-specific eyes/mouth, gold antenna, blush — matching `orbit-expressions.html`. Use `AppColors` tokens (`#5B4FE9`, `#E0A82E`, mint `#66E0C8`). Respect `MediaQuery.disableAnimations` (reduced motion) by holding a static frame.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/orbit_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/presentation/orbit.dart test/features/focus/orbit_test.dart
git commit -m "feat(focus): add Orbit mascot widget"
```

---

### Task 11: Focus task card (kind-driven template)

**Files:**
- Create: `lib/features/focus/presentation/focus_task_card.dart`
- Test: `test/features/focus/focus_task_card_test.dart`

Visual reference: the guided-task frames in `focus-mode-full.html` (payment / reply / offer variants). The card takes an `AiWorkItem` and callbacks; it renders the kind pill, `focusLabel(item)` title, why-line (`item.context`), customer chip, kind-specific body (AI draft / incoming message / offer summary), the primary CTA from `resolveFocusAction`, and Skip / Mark-done.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_task_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/focus_task_card.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

AiWorkItem _pay() => const AiWorkItem(
    id: 'a', kind: 'overdue_payment', priority: 'high', score: 9, title: 't',
    status: 'pending', batchId: 'b1', customerName: 'Aman Gupta', amount: 8597,
    draftMessage: 'Gentle reminder about ₹8,597');

void main() {
  testWidgets('payment card shows title, customer and primary CTA', (tester) async {
    var primaryTapped = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FocusTaskCard(
      item: _pay(),
      onPrimary: () => primaryTapped = true,
      onSkip: () {},
      onMarkDone: () {},
      canSkip: true,
    ))));

    expect(find.text('Aman Gupta'), findsOneWidget);
    expect(find.textContaining('Send'), findsWidgets); // primary verb
    await tester.tap(find.byKey(const Key('focus_primary')));
    expect(primaryTapped, isTrue);
  });

  testWidgets('hides skip when canSkip is false', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FocusTaskCard(
      item: _pay(), onPrimary: () {}, onSkip: () {}, onMarkDone: () {},
      canSkip: false))));
    expect(find.byKey(const Key('focus_skip')), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_task_card_test.dart`
Expected: FAIL — `focus_task_card.dart` does not exist.

- [ ] **Step 3: Implement**

Build `FocusTaskCard` with this signature and the body/CTA mapping described above:

```dart
class FocusTaskCard extends StatelessWidget {
  const FocusTaskCard({
    super.key,
    required this.item,
    required this.onPrimary,
    required this.onSkip,
    required this.onMarkDone,
    required this.canSkip,
  });
  final AiWorkItem item;
  final VoidCallback onPrimary, onSkip, onMarkDone;
  final bool canSkip;
  // ...
}
```

Primary button gets `key: Key('focus_primary')`; skip gets `key: Key('focus_skip')` and is omitted when `!canSkip`. Map `resolveFocusAction(item.kind)` → `{label, icon, colour}` (reminder/reply/offer = WhatsApp green `AppColors.success`; openWorkspace = indigo). Use `focusLabel(item)` for the title and `AppColors`/`AppSpacing`/`AppRadius` tokens.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_task_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/presentation/focus_task_card.dart test/features/focus/focus_task_card_test.dart
git commit -m "feat(focus): add kind-driven focus task card"
```

---

### Task 12: Static screens — entry, resume, empty, success, finish

**Files:**
- Create: `lib/features/focus/presentation/focus_screens.dart`
- Test: `test/features/focus/focus_screens_test.dart`

Visual reference: Entry/Success/Finish/Empty/Resume frames in `focus-mode-full.html`. Each is a stateless widget taking plain data + callbacks (no provider reads) so it renders in isolation.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_screens_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/focus_screens.dart';
import 'package:orderly_app/features/focus/data/focus_session.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

void main() {
  testWidgets('entry shows scope pill and start callback fires', (tester) async {
    var started = false;
    await tester.pumpWidget(MaterialApp(home: FocusEntryScreen(
      firstName: 'Rahul', taskCount: 5, minutes: 10,
      onStart: () => started = true, onDismiss: () {})));
    expect(find.textContaining('5 tasks'), findsOneWidget);
    await tester.tap(find.byKey(const Key('focus_start')));
    expect(started, isTrue);
  });

  testWidgets('finish shows summary tallies', (tester) async {
    const summary = FocusSummary(tasksCompleted: 5, paymentsFollowedUp: 2,
      amountFollowedUp: 19400, repliesSent: 2, offersSent: 1);
    await tester.pumpWidget(MaterialApp(home: FocusFinishScreen(
      firstName: 'Rahul', summary: summary, onDone: () {})));
    expect(find.textContaining('5'), findsWidgets);
    expect(find.byKey(const Key('focus_done')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_screens_test.dart`
Expected: FAIL — `focus_screens.dart` does not exist.

- [ ] **Step 3: Implement**

Create these stateless widgets in `focus_screens.dart`, matching the mockup:

```dart
class FocusEntryScreen extends StatelessWidget {   // + resume variant via optional `resumeLeft`
  const FocusEntryScreen({super.key, required this.firstName,
    required this.taskCount, required this.minutes,
    required this.onStart, required this.onDismiss, this.resumeLeft});
  // key('focus_start') on the primary button
}
class FocusEmptyScreen extends StatelessWidget { /* onBackHome */ }
class FocusSuccessOverlay extends StatelessWidget { /* progress, line, checkmark */ }
class FocusFinishScreen extends StatelessWidget {  // key('focus_done')
  const FocusFinishScreen({super.key, required this.firstName,
    required this.summary, required this.onDone});
}
```

Use the indigo gradient (`AppColors.briefGradientStart/End`), `Orbit` at the moods from the mockup (entry=neutral, empty/finish=happy/celebrating), and the deterministic copy from `focus_copy.dart`. `FocusSuccessOverlay` draws the checkmark via `CustomPaint` + a short `AnimationController`; it calls back `onDone` when the animation completes (route uses this to `advance()`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_screens_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/presentation/focus_screens.dart test/features/focus/focus_screens_test.dart
git commit -m "feat(focus): add entry/empty/success/finish screens"
```

---

### Task 13: Overlays — skip sheet, exit dialog, error toast

**Files:**
- Create: `lib/features/focus/presentation/focus_overlays.dart`
- Test: `test/features/focus/focus_overlays_test.dart`

Visual reference: the skip / exit / error frames in `focus-mode-full.html`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/focus/focus_overlays_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/focus_overlays.dart';

void main() {
  testWidgets('exit dialog returns true on Leave, false on Keep going',
      (tester) async {
    late bool? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => result = await showFocusExitDialog(ctx, done: 1, total: 5),
        child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Leave Focus Mode'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_overlays_test.dart`
Expected: FAIL — `focus_overlays.dart` does not exist.

- [ ] **Step 3: Implement**

```dart
// signatures
Future<bool> showFocusExitDialog(BuildContext c, {required int done, required int total});
Future<bool> showFocusSkipSheet(BuildContext c, {required String customerName});
Widget focusErrorToast({required String customerName, required VoidCallback onRetry});
```

`showFocusExitDialog` returns `true` when the user taps **Leave**, `false`/`null` for **Keep going**. `showFocusSkipSheet` returns `true` when **Skip →** is tapped. Match the mockup (Orbit thinking on the sheet, indigo emphasis on the retained action). Reduced-motion safe.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_overlays_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/focus/presentation/focus_overlays.dart test/features/focus/focus_overlays_test.dart
git commit -m "feat(focus): add skip/exit/error overlays"
```

---

### Task 14: Focus mode route (assembles the flow + persistence + actions)

**Files:**
- Create: `lib/features/focus/presentation/focus_mode_route.dart`
- Test: `test/features/focus/focus_mode_route_test.dart`

This wires everything: `FocusMode.start(context)` loads work items, builds/resumes the
session, and renders the current `FocusStatus`. It owns the WhatsApp launch, persistence
(`FocusSessionStore`), and the success→advance timing.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/focus/focus_mode_route_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orderly_app/features/focus/presentation/focus_mode_route.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';
import 'package:orderly_app/features/work/data/ai_work_items_service.dart';

class _Svc implements AiWorkItemsService {
  @override
  Future<List<AiWorkItem>> fetchPending() async => const [AiWorkItem(
    id: 'a', kind: 'overdue_payment', priority: 'high', score: 9, title: 't',
    status: 'pending', batchId: 'b1', customerName: 'Aman Gupta', amount: 8597)];
  @override
  Future<void> approve(String id) async {}
  @override
  Future<void> markDone(String id) async {}
  @override
  Future<void> dismiss(String id) async {}
  @override
  Future<void> updateStatus(String id, String s) async {}
  @override
  Future<void> triggerGenerate() async {}
}

void main() {
  testWidgets('opens entry when work exists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(overrides: [
      aiWorkItemsServiceProvider.overrideWithValue(_Svc()),
    ], child: const MaterialApp(home: FocusModeView())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('focus_start')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/focus/focus_mode_route_test.dart`
Expected: FAIL — `focus_mode_route.dart` does not exist.

- [ ] **Step 3: Implement**

Create `FocusModeView` (a `ConsumerStatefulWidget`) and the launcher:

```dart
class FocusMode {
  static Future<void> start(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const FocusModeView()));
}
```

`FocusModeView` responsibilities:
1. On init: `await workItemsProvider.load()` if needed, read `FocusSessionStore` (from `SharedPreferences.getInstance()`), decide **resume vs entry vs empty** using `FocusSnapshot.isResumable`.
2. Render current `FocusStatus` with a fade-through `AnimatedSwitcher`: entry→`FocusEntryScreen`, active→`FocusTaskCard` (+ progress header + inline `focusTaskLead`), celebrating→`FocusSuccessOverlay`, finished→`FocusFinishScreen`, empty→`FocusEmptyScreen`.
3. Primary action: for send-kinds, launch `https://wa.me/91${item.phone}` with the prefilled `draftMessage` (reuse the `customer_workspace_screen.dart` pattern); on success `notifier.completeCurrent()`, persist snapshot, fire `HapticFeedback.mediumImpact()`; on `launchUrl` failure show `focusErrorToast`.
4. Success overlay `onDone` → `notifier.advance()`; on finish → `store.clear()`.
5. Back button / ✕ → `showFocusExitDialog`; **Leave** pops the route (progress already persisted).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/focus/focus_mode_route_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the whole focus suite + analyze**

Run: `flutter test test/features/focus && flutter analyze lib/features/focus`
Expected: all PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/focus/presentation/focus_mode_route.dart test/features/focus/focus_mode_route_test.dart
git commit -m "feat(focus): assemble focus mode route with persistence and actions"
```

---

### Task 15: Wire the two entry points

**Files:**
- Modify: `lib/features/today/presentation/today_screen.dart:851`
- Modify: `lib/features/work/presentation/my_work_screen.dart`
- Test: `test/features/today/today_screen_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

Extend `today_screen_test.dart` to assert the CTA pushes the Focus route (rather than only calling `onNavigate(1)`):

```dart
  testWidgets('Start My Work opens Focus Mode', (tester) async {
    // pump TodayScreen inside a MaterialApp with a NavigatorObserver spy,
    // tap find.text('Start My Work →'), then:
    expect(find.byType(FocusModeView), findsOneWidget);
  });
```

(Use the existing TodayScreen test harness/imports already in the file; add
`import '.../focus/presentation/focus_mode_route.dart';`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/today/today_screen_test.dart`
Expected: FAIL — CTA still only switches tabs.

- [ ] **Step 3: Implement**

In `today_screen.dart`, change the `Start My Work →` button's `onPressed` from
`() => widget.onNavigate(1)` to `() => FocusMode.start(context)` and add the import.
In `my_work_screen.dart`, add a primary `Start My Work` button (app-bar action or a
header CTA) calling `FocusMode.start(context)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/today/today_screen_test.dart test/features/work`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/today/presentation/today_screen.dart lib/features/work/presentation/my_work_screen.dart test/features/today/today_screen_test.dart
git commit -m "feat(focus): launch Focus Mode from Start My Work CTAs"
```

---

### Task 16: Full-suite green + analyze

**Files:** none (verification).

- [ ] **Step 1: Run the full suite**

Run: `flutter test`
Expected: all PASS (focus suite + untouched existing tests, including brief/today/work).

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 3: Manual smoke (device/emulator)**

Launch app → Home → `Start My Work →` → complete one payment (WhatsApp opens) →
success animation → next task → exit → relaunch → resume. Confirm a completed item
disappears from the My Work tab (sync).

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "test(focus): stabilise full suite for Focus Mode"
```

---

## Self-Review

**Spec coverage:** Entry(T12) · guided task(T11) · success(T12) · next-task transition(T14 AnimatedSwitcher) · skip(T3 logic + T13 sheet) · exit dialog(T13) · all-complete(T12) · empty(T9/T12) · error(T13/T14) · resume(T7 rule + T8 store + T14 branch). Task template kind mapping(T6/T11). Progress + copy(T3/T5). Persistence(T7/T8/T14). Sync back to app(T9 via workItemsProvider). Motion/haptics/a11y(T10/T12/T14 notes). Entry points(T15). All spec sections map to a task.

**Placeholder scan:** Pure-logic tasks (1–9) carry complete code + tests. Presentation tasks (10–14) give exact signatures, keyed test assertions, and point to the approved mockup HTML as the single source of pixel truth — deliberate DRY, not a gap.

**Type consistency:** `FocusSession` API (`current`, `complete()`, `skip()`, `canSkip`, `remainingMinutes`, `summary()`, `sessionTotal`, `progress`, `position`) is used identically across T2–T4, T9, T14. `FocusStatus` enum values match between T9 and T14. `resolveFocusAction`/`FocusActionKind` (T6) consumed in T11. `FocusSnapshot.isResumable` (T7) consumed in T14. Store method names (`save`/`read`/`clear`) consistent T8↔T14.
