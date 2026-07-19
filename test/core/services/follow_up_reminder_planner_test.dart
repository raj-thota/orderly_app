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
      int constId(String a, String b) => 42;
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

  group('parseFollowUpDate', () {
    test('normalizes a UTC ISO string to local time', () {
      final parsed = parseFollowUpDate('2026-07-19T00:00:00Z');
      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse);
    });

    test('normalizes a UTC DateTime to local', () {
      final parsed = parseFollowUpDate(DateTime.utc(2026, 7, 19));
      expect(parsed!.isUtc, isFalse);
    });

    test('returns null for null or unparseable input', () {
      expect(parseFollowUpDate(null), isNull);
      expect(parseFollowUpDate('not-a-date'), isNull);
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
