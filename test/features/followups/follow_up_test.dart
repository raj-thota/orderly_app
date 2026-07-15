import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/followups/data/follow_up.dart';

void main() {
  final today = DateTime(2026, 7, 15, 10, 0);

  test('fromMap parses all fields', () {
    final f = FollowUp.fromMap({
      'id': 'fu1',
      'user_id': 'u1',
      'customer_id': 'c1',
      'lead_id': 'l1',
      'due_at': '2026-07-15T09:00:00.000Z',
      'note': 'Call about payment',
      'kind': 'payment',
      'status': 'pending',
      'created_at': '2026-07-10T08:00:00.000Z',
    });

    expect(f.id, 'fu1');
    expect(f.customerId, 'c1');
    expect(f.leadId, 'l1');
    expect(f.dueAt, DateTime.parse('2026-07-15T09:00:00.000Z'));
    expect(f.note, 'Call about payment');
    expect(f.kind, 'payment');
    expect(f.status, 'pending');
  });

  test('fromMap defaults kind to general and status to pending', () {
    final f = FollowUp.fromMap({
      'id': 'fu2',
      'customer_id': 'c1',
      'due_at': '2026-07-20T00:00:00.000Z',
    });
    expect(f.kind, 'general');
    expect(f.status, 'pending');
    expect(f.note, isNull);
    expect(f.leadId, isNull);
  });

  test('fromMap reads customer name from join', () {
    final f = FollowUp.fromMap({
      'id': 'fu3',
      'customer_id': 'c1',
      'due_at': '2026-07-15T00:00:00.000Z',
      'customers': {'name': 'Rahul Verma', 'phone': '9123456789'},
    });
    expect(f.customerName, 'Rahul Verma');
    expect(f.customerPhone, '9123456789');
  });

  test('isPending returns true for pending status', () {
    final f = FollowUp.fromMap({
      'id': 'fu4', 'customer_id': 'c1',
      'due_at': '2026-07-15T00:00:00.000Z', 'status': 'pending',
    });
    expect(f.isPending, isTrue);
    final done = FollowUp.fromMap({
      'id': 'fu5', 'customer_id': 'c1',
      'due_at': '2026-07-15T00:00:00.000Z', 'status': 'done',
    });
    expect(done.isPending, isFalse);
  });

  test('isOverdue returns true when due_at is before start of today', () {
    // Use UTC noon on July 10 — clearly before July 15 in any timezone.
    final overdue = FollowUp.fromMap({
      'id': 'fu6', 'customer_id': 'c1',
      'due_at': '2026-07-10T12:00:00.000Z',
    });
    expect(overdue.isOverdue(now: today), isTrue);

    // UTC noon on July 16 — clearly after July 15 in any timezone.
    final upcoming = FollowUp.fromMap({
      'id': 'fu7', 'customer_id': 'c1',
      'due_at': '2026-07-16T12:00:00.000Z',
    });
    expect(upcoming.isOverdue(now: today), isFalse);
  });

  test('isDueToday returns true when due_at falls on today', () {
    // UTC 06:00 on July 15 = 11:30 AM IST on July 15 — safely "today" in IST.
    final dueToday = FollowUp.fromMap({
      'id': 'fu8', 'customer_id': 'c1',
      'due_at': '2026-07-15T06:00:00.000Z',
    });
    expect(dueToday.isDueToday(now: today), isTrue);

    // UTC noon on July 16 — clearly tomorrow.
    final tomorrow = FollowUp.fromMap({
      'id': 'fu9', 'customer_id': 'c1',
      'due_at': '2026-07-16T12:00:00.000Z',
    });
    expect(tomorrow.isDueToday(now: today), isFalse);
  });

  test('isOverdue is false for due_at in the middle of today', () {
    // UTC 06:00 on July 15 = 11:30 AM IST July 15 — during today, not overdue.
    final duringToday = FollowUp.fromMap({
      'id': 'fu10', 'customer_id': 'c1',
      'due_at': '2026-07-15T06:00:00.000Z',
    });
    expect(duringToday.isOverdue(now: today), isFalse);
    expect(duringToday.isDueToday(now: today), isTrue);
  });

  test('toNotificationMap converts to legacy notification format', () {
    final f = FollowUp.fromMap({
      'id': 'fu11',
      'customer_id': 'c1',
      'due_at': '2026-07-15T09:00:00.000Z',
      'customers': {'name': 'Meena Joshi'},
    });
    final map = f.toNotificationMap();
    expect(map['id'], 'fu11');
    expect(map['name'], 'Meena Joshi');
    // Compare parsed DateTime to avoid ISO format differences (3 vs 6 decimal places).
    expect(DateTime.tryParse(map['follow_up_date'] as String), f.dueAt);
    expect(map['status'], 'follow');
  });
}
