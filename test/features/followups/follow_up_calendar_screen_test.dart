import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart'
    show followUpsServiceProvider;
import 'package:orderly_app/features/followups/data/follow_up.dart';
import 'package:orderly_app/features/followups/presentation/follow_up_calendar_screen.dart';

import '../../features/enquiries/capture_controller_test.dart'
    show FakeFollowUpsService;

class ScreenCalFake extends FakeFollowUpsService {
  final Map<String, List<FollowUp>> byWeek;
  ScreenCalFake(this.byWeek);

  @override
  Future<List<FollowUp>> fetchForWeek(DateTime weekStart) async =>
      byWeek['${weekStart.year}-${weekStart.month}-${weekStart.day}'] ?? [];
}

FollowUp _fu(String id, DateTime dueAt, {String? name}) => FollowUp(
      id: id,
      customerId: 'c1',
      dueAt: dueAt,
      kind: 'general',
      status: 'pending',
      customerName: name ?? 'Test Customer',
    );

Widget _wrap(ScreenCalFake fake) => ProviderScope(
      overrides: [followUpsServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: FollowUpCalendarScreen()),
    );

void main() {
  testWidgets('shows Follow-up Calendar title', (t) async {
    await t.pumpWidget(_wrap(ScreenCalFake({})));
    await t.pumpAndSettle();
    expect(find.textContaining('Follow-up'), findsWidgets);
  });

  testWidgets('shows 7 day abbreviations in week strip', (t) async {
    await t.pumpWidget(_wrap(ScreenCalFake({})));
    await t.pumpAndSettle();
    for (final abbr in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
      expect(find.text(abbr), findsOneWidget);
    }
  });

  testWidgets('shows follow-up customer name for selected day', (t) async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final key = '${weekStart.year}-${weekStart.month}-${weekStart.day}';
    final fake = ScreenCalFake({
      key: [_fu('fu1', weekStart, name: 'Meena Joshi')],
    });
    await t.pumpWidget(_wrap(fake));
    await t.pumpAndSettle();
    await t.tap(find.text('Mon'));
    await t.pumpAndSettle();
    expect(find.text('Meena Joshi'), findsOneWidget);
  });

  testWidgets('shows empty state when no follow-ups for selected day', (t) async {
    await t.pumpWidget(_wrap(ScreenCalFake({})));
    await t.pumpAndSettle();
    expect(find.textContaining('No follow-ups'), findsOneWidget);
  });

  testWidgets('mark done button is present on a follow-up card', (t) async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final key = '${weekStart.year}-${weekStart.month}-${weekStart.day}';
    final fake = ScreenCalFake({
      key: [_fu('fu1', weekStart, name: 'Rahul')],
    });
    await t.pumpWidget(_wrap(fake));
    await t.pumpAndSettle();
    await t.tap(find.text('Mon'));
    await t.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
  });
}
