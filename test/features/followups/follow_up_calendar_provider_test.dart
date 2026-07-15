import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart'
    show followUpsServiceProvider;
import 'package:orderly_app/features/followups/controller/follow_up_calendar_provider.dart';
import 'package:orderly_app/features/followups/data/follow_up.dart';

import '../../features/enquiries/capture_controller_test.dart'
    show FakeFollowUpsService;

class _CalFake extends FakeFollowUpsService {
  final Map<String, List<FollowUp>> byWeek;
  final List<String> doneCalled = [];
  final List<String> skippedCalled = [];

  _CalFake(this.byWeek);

  static String _key(DateTime weekStart) =>
      '${weekStart.year}-${weekStart.month}-${weekStart.day}';

  @override
  Future<List<FollowUp>> fetchForWeek(DateTime weekStart) async =>
      byWeek[_key(weekStart)] ?? [];

  @override
  Future<void> markDone(String id) async => doneCalled.add(id);

  @override
  Future<void> markSkipped(String id) async => skippedCalled.add(id);
}

FollowUp _fu(String id, DateTime dueAt, {String? name}) => FollowUp(
      id: id,
      customerId: 'c1',
      dueAt: dueAt,
      kind: 'general',
      status: 'pending',
      customerName: name ?? 'Test Customer',
    );

ProviderContainer _container(_CalFake fake) {
  final c = ProviderContainer(overrides: [
    followUpsServiceProvider.overrideWithValue(fake),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  final monday = DateTime(2026, 7, 13); // Monday

  test('loads follow-ups for current week on init', () async {
    final fake = _CalFake({
      '2026-7-13': [_fu('fu1', DateTime(2026, 7, 14, 10, 0))],
    });
    final c = _container(fake);
    await c.read(followUpCalendarProvider.notifier).load();
    expect(c.read(followUpCalendarProvider).followUps, hasLength(1));
  });

  test('nextWeek advances weekStart by 7 days', () async {
    final fake = _CalFake({
      '2026-7-13': [],
      '2026-7-20': [_fu('fu2', DateTime(2026, 7, 21, 10, 0))],
    });
    final c = _container(fake);
    await c.read(followUpCalendarProvider.notifier).load();
    await c.read(followUpCalendarProvider.notifier).nextWeek();
    final state = c.read(followUpCalendarProvider);
    expect(state.weekStart.day, monday.add(const Duration(days: 7)).day);
    expect(state.followUps, hasLength(1));
  });

  test('prevWeek retreats weekStart by 7 days', () async {
    final fake = _CalFake({
      '2026-7-6': [_fu('fu3', DateTime(2026, 7, 7, 10, 0))],
      '2026-7-13': [],
    });
    final c = _container(fake);
    await c.read(followUpCalendarProvider.notifier).load();
    await c.read(followUpCalendarProvider.notifier).prevWeek();
    final state = c.read(followUpCalendarProvider);
    expect(state.weekStart.day, monday.subtract(const Duration(days: 7)).day);
    expect(state.followUps, hasLength(1));
  });

  test('followUpsForDay returns only items due on that day', () async {
    final tuesday = DateTime(2026, 7, 14, 10, 0);
    final wednesday = DateTime(2026, 7, 15, 10, 0);
    final fake = _CalFake({
      '2026-7-13': [
        _fu('a', tuesday),
        _fu('b', tuesday),
        _fu('c', wednesday),
      ],
    });
    final c = _container(fake);
    await c.read(followUpCalendarProvider.notifier).load();
    final state = c.read(followUpCalendarProvider);
    expect(state.followUpsForDay(tuesday), hasLength(2));
    expect(state.followUpsForDay(wednesday), hasLength(1));
  });

  test('markDone calls service and removes item from list', () async {
    final fake = _CalFake({
      '2026-7-13': [_fu('fu1', DateTime(2026, 7, 14, 10, 0))],
    });
    final c = _container(fake);
    await c.read(followUpCalendarProvider.notifier).load();
    await c.read(followUpCalendarProvider.notifier).markDone('fu1');
    expect(c.read(followUpCalendarProvider).followUps, isEmpty);
    expect(fake.doneCalled, ['fu1']);
  });
}
