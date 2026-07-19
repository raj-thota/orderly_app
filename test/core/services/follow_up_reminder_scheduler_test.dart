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

  test('concurrent syncs are serialized and both lead sets are processed',
      () async {
    final sched = await build();
    final a = sched.sync([lead('l1', DateTime(2026, 7, 17))]);
    final b = sched.sync([lead('l2', DateTime(2026, 7, 16))]);
    await Future.wait<void>([a, b]);
    // The drain loop runs once more for the second sync, so both lead sets are
    // reconciled and each is scheduled exactly once — no duplicates.
    final schedPayloads = scheduled.map((r) => r.payload).toList();
    expect(schedPayloads.toSet(), containsAll(<String>['l1', 'l2']));
    expect(schedPayloads.length, schedPayloads.toSet().length);
  });
}
