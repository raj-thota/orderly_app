# Notification Reliability — Design

**Date:** 2026-07-19
**Branch:** `feat/notification-reliability`
**Status:** Approved (design), pending spec review

## Problem

The existing notification system has two disconnected halves and a set of concrete
reliability bugs. This work fixes the **device (OS) notification** half so it never
duplicates and always taps through to the correct screen, cleans up the code, and
applies a light polish to the in-app Notification Center.

### Current architecture (as-is)

**A) OS local notifications — `lib/core/services/notification_service.dart`** (597 lines,
static god-class)

- Uses `flutter_local_notifications` **only**. There is no FCM/APNs/push anywhere in the
  repo. Every "device notification" is a locally-scheduled follow-up / overdue lead
  reminder.
- Tap payload is a bare `leadId` string and always routes to exactly one destination:
  the enquiry / lead detail screen (`LeadNavigationService` pushed on the global
  `navigatorKey`).
- Scheduled from four uncoordinated call sites: `main.dart` home `initState`,
  `review_confirm_screen.dart`, and `capture_screen.dart` (twice).

**B) In-app Notification Center — `lib/features/notifications/presentation/notifications_screen.dart`**
(336 lines)

- Driven by Riverpod `workItemsProvider` (AI work items, same source as the bell badge).
  Has **zero** connection to system A.
- Groups items into "🔥 Urgent" (high) vs "Needs attention" (medium+low). No read/unread,
  timestamps, swipe actions, or mark-all. Tap opens `CustomerWorkspaceScreen`.

### Confirmed bugs

1. **Duplicate root cause (overdue leads):** `syncLeadNotifications` fires **both**
   `scheduleNotification(repeatDaily 9am)` **and** an instant `_showOncePerDay` using the
   **same notification id** (`notification_service.dart:419-435`). The user sees two.
2. **`repeatDaily` overdue reminders** persist and re-fire daily until a later sync
   cancels them.
3. **Id collisions:** `_notificationId = Object.hash(leadId, type) & 0x7fffffff` can
   collide across different lead ids → a cancel for one lead can clear another's
   notification.
4. **Unbounded SharedPreferences growth:** per-day receipt keys
   (`follow_up_notification_<type>_<leadId>_<day>`) are written but never pruned.
5. **No lifecycle re-sync:** there is no `WidgetsBindingObserver`; reminders are only
   evaluated at cold start and from scattered mutation call sites.
6. **Concurrency race:** multiple uncoordinated call sites can run
   `syncLeadNotifications` concurrently. Each does read-then-write on the shared prefs
   id list and per-day receipts → lost updates and, in the worst case, a duplicate
   instant show.
7. **Tap-nav fragility:** `_queueLeadNavigation` re-queues itself via
   `addPostFrameCallback` unbounded until the navigator is ready, and the cold-start
   launch-details path plus the runtime callback can both fire for the same tap with no
   dedupe → potential double navigation.
8. **Dead code (~110 lines):** `buildBuckets`, `buildSuggestions`,
   `NotificationSuggestion`, `NotificationBuckets`, and their private helpers
   (`_isHighIntentLead`, `_isClosedLead`, `_friendlyFollowUpLabel`) have zero usages
   outside the file.

## Scope (locked with the user)

**In scope**

- Device-notification reliability: eliminate duplicates; correct tap navigation to the
  lead-detail screen across all app states (terminated / background / foreground);
  correct lifecycle behavior.
- Code cleanup: split the god-class, delete dead code, remove the SharedPreferences
  receipt bloat, remove id-collision risk.
- **Light** Notification Center polish that needs no new data model.

**Out of scope**

- No push/FCM backend.
- No new notification *types* or destinations (Orders, Payments, Customer Chat, Start My
  Work, AI Brief, Business Insights). The only device notification remains the follow-up
  reminder, and its only tap destination remains lead detail. A type-routed deep-link
  router is explicitly deferred.
- No read/unread persistence in the Notification Center (would need new storage).

## Chosen approach — Reconcile engine, no instant show (Approach B)

Model the desired notifications as a **pure function** of the current leads, then
**reconcile** that plan against the OS's own pending-notification set. This makes sync
idempotent by construction and removes every duplicate vector: there is one mechanism
(scheduled only), no instant-on-open show, no prefs receipts, and no id collisions.

The user accepted the behavioral tradeoff: the OS no longer fires a follow-up
notification the instant the app is opened. On-open urgency is surfaced **in-app** via the
bell / Notification Center, not as an OS notification. Reminders fire at their scheduled
time; an overdue lead gets one daily reminder at 09:00.

### Units and responsibilities

**1. `lib/core/services/follow_up_reminder_planner.dart` — new, pure (no plugin/Flutter deps)**

Owns the "what should be scheduled" decision so it can be unit-tested in isolation.

- Moves the existing pure helpers here: `parseFollowUpDate`, `isFollowUpToday`,
  `isOverdueFollowUp`, `needsFollowUpAttention`, `_notificationTimeForFollowUp`,
  `_nextOverdueReminderTime`, and `_defaultReminderHour`.
- Value type:

  ```dart
  class PlannedReminder {
    final int id;
    final DateTime when;      // local wall-clock; scheduler converts to tz
    final String title;
    final String body;
    final String payload;     // leadId
    final bool repeatDaily;
  }
  ```

- API:

  ```dart
  List<PlannedReminder> plan(
    List<Map<String, dynamic>> leads, {
    DateTime? now,
    required int Function(String leadId, String type) idFor,
  });
  ```

  Rules, per lead with `status == 'follow'` and a parseable `follow_up_date`:
  - **overdue** → one reminder, `when = nextOverdueReminderTime(now)`,
    `repeatDaily = true`, `id = idFor(leadId, 'overdue')`,
    title `"Overdue follow-up"`, body `"<name> still needs your attention."`
  - **future follow-up time** → one reminder, `when = notificationTime`,
    `repeatDaily = false`, `id = idFor(leadId, 'follow_up')`,
    title `"Follow-up reminder"`, body `"Reach out to <name> on time."`
  - **due today but time already passed** → **no reminder** (dropped on-open nudge).
  - any other lead → produces nothing; reconcile cancels any leftover.

  De-dupes by id within a single plan.

**2. `reconcile()` — pure function (co-located with the planner)**

```dart
class ReconcilePlan {
  final List<PlannedReminder> toSchedule;
  final List<int> toCancel;
}

ReconcilePlan reconcile(List<PlannedReminder> planned, Set<int> currentPendingIds);
```

- `toCancel = currentPendingIds − plannedIds`
- `toSchedule = planned` (re-scheduling by id replaces in place, keeping body text fresh
  without firing the notification)

Unit-testable without touching the plugin.

**3. `lib/core/services/notification_id_registry.dart` — new, small**

- Persists a `"<leadId>:<type>" → int` map in SharedPreferences with a monotonic counter,
  so ids are unique (no `Object.hash` collisions) and stable across runs (cancels match
  what was scheduled).
- `Future<int> idFor(String leadId, String type)` — returns the existing id or assigns
  the next counter value. Ids stay in `[1, 2^31)`.

**4. `lib/core/services/notification_service.dart` — rewritten, thin**

OS wrapper + reconcile orchestration + tap navigation.

- **Idempotent `init()`** guarded by a `_initialized` flag: init plugin, create the
  Android channel, request iOS/Android + exact-alarm permissions, register the tap
  callback **once**, and handle `getNotificationAppLaunchDetails()` **once**.
- Primitives: `schedule(PlannedReminder)`, `cancel(int id)`, `cancelAll()`,
  `Future<Set<int>> pendingIds()` (wraps `pendingNotificationRequests()`).
- `syncFollowUpReminders({List<Map<String, dynamic>>? leads})`:
  - **Serialized**: a single in-flight guard. If a sync is already running, set a `_dirty`
    flag and return; when the running sync finishes, if `_dirty` it runs exactly once
    more. Prevents concurrent reconcile races.
  - Build `idFor` from the registry → `planned = plan(leads, idFor)` →
    `current = await pendingIds()` → `reconcile(planned, current)` → cancel `toCancel`,
    schedule `toSchedule`.
  - **No instant show. No prefs receipts.**
- `checkAndTriggerSmartReminders()` retained as the public entry point (keeps the existing
  `follow_ups` → legacy-leads fallback), now delegating to `syncFollowUpReminders` — so
  existing call sites change minimally.
- **Tap navigation hardened** — `_handlePayload(String? leadId)`:
  - Idempotent: dedupe the launch-details-vs-runtime-callback double for the same tap via
    a last-handled guard.
  - Bounded navigator-ready wait (a small retry cap or a `Completer` resolved when
    `navigatorKey.currentState` is available), replacing the unbounded self-re-queue.
  - Pushes `LeadNavigationService.leadDetailRoute` on `navigatorKey`.
- **Deleted:** `showNotification`, `_showOncePerDay`, `_dailyReceiptKey`,
  `_scheduledLeadIdsKey` and its prev/current diff logic, `buildBuckets`,
  `buildSuggestions`, `NotificationSuggestion`, `NotificationBuckets`, `_isHighIntentLead`,
  `_isClosedLead`, `_friendlyFollowUpLabel`.

**5. Lifecycle**

- Add a `WidgetsBindingObserver` at the app root (home shell). On
  `AppLifecycleState.resumed` it calls `checkAndTriggerSmartReminders()`, which funnels
  through the serialized sync (safe under concurrency).
- Keep the cold-start trigger in `main.dart` home `initState`.
- Collapse the duplicate `syncLeadNotifications` call in `capture_screen.dart`
  (lines 247 + 271) to a single call. Mutation-driven triggers in
  `review_confirm_screen.dart` and `capture_screen.dart` remain but now route through the
  serialized entry.

**6. One-time migration**

Old-scheme notifications were scheduled with `Object.hash` ids; the new registry assigns
different ids, so a stale reconcile can't cancel them. On first run after this change, a
prefs-flag-guarded migration calls `cancelAll()` and clears the legacy
`scheduled_follow_up_lead_ids` list and any `follow_up_notification_*` receipt keys, then
lets the next sync schedule fresh. Prevents orphaned old notifications lingering.

## Notification Center — light polish

File: `lib/features/notifications/presentation/notifications_screen.dart`. No new storage,
no read/unread.

- **Relative timestamps** per tile from `item.createdAt` (a small `_relativeTime` helper;
  rendered only when non-null). `AiWorkItem` already carries `createdAt` and `expiresAt`.
- **Swipe-to-dismiss**: wrap each tile in `Dismissible` (key = `item.id`) calling the
  existing `workItemsProvider.notifier.dismiss(id)`, with an undo `SnackBar`.
- **Mark all done**: an app-bar action backed by a thin `markAllDone()` added to
  `WorkItemsNotifier` that reuses `markDone` semantics (optimistic clear + per-id service
  call).
- Keep the high/others grouping. Tidy the empty state. Render with `ListView.builder`.

## Error handling

- All OS calls stay best-effort; `checkAndTriggerSmartReminders` keeps its try/catch and
  `follow_ups` → legacy fallback.
- The serialized sync swallows and logs per-lead scheduling failures without aborting the
  whole reconcile.
- Tap navigation no-ops safely when the payload is empty or the navigator never becomes
  available within the bounded wait.
- Center dismiss/mark-all are optimistic with rollback on service failure (existing
  provider pattern).

## Testing (TDD)

- `test/.../follow_up_reminder_planner_test.dart` — overdue → daily 09:00 plan; future →
  scheduled; today-but-passed → none; non-follow / unparseable date → none; id de-dupe;
  `now` injected.
- `reconcile` unit tests — cancel-stale, schedule-missing, empty plan cancels all,
  no-op when plan equals current.
- `test/.../notification_id_registry_test.dart` — stable across calls, unique per
  key, persisted across instances.
- Tap-nav idempotency — extract the dedupe decision into a testable unit and assert a
  single navigation for the launch-details-plus-callback double.
- Update `test/features/notifications/notifications_screen_test.dart` for swipe-to-dismiss,
  timestamp rendering, and mark-all-done.

## Risks / tradeoffs

- **Behavioral change:** no on-open OS nudge (accepted). If product later wants an
  immediate nudge it belongs in-app, not as an OS notification.
- **Migration cancels all pending once:** any legitimately-scheduled reminder is
  re-created by the immediately-following sync, so the visible effect is nil.
- **`pendingNotificationRequests()` platform quirks:** on some platforms delivered (not
  pending) notifications aren't listed; acceptable because our reconcile only manages
  future/pending reminders and repeat-daily reminders remain pending between fires.
