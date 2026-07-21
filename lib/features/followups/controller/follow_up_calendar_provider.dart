import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart'
    show followUpsServiceProvider;
import 'package:orderly_app/features/followups/data/follow_up.dart';
import 'package:orderly_app/features/followups/data/follow_ups_service.dart';

class FollowUpCalendarState {
  const FollowUpCalendarState({
    required this.weekStart,
    this.followUps = const [],
    this.loading = false,
  });

  final DateTime weekStart;
  final List<FollowUp> followUps;
  final bool loading;

  List<FollowUp> followUpsForDay(DateTime day) =>
      followUps.where((f) => f.isDueToday(now: day)).toList();
}

class FollowUpCalendarNotifier
    extends StateNotifier<FollowUpCalendarState> {
  FollowUpCalendarNotifier(this._service, DateTime weekStart)
      : super(FollowUpCalendarState(weekStart: weekStart));

  final FollowUpsService _service;

  Future<void> load() async {
    state = FollowUpCalendarState(weekStart: state.weekStart, loading: true);
    final items = await _service.fetchForWeek(state.weekStart);
    if (mounted) {
      state = FollowUpCalendarState(weekStart: state.weekStart, followUps: items);
    }
  }

  Future<void> nextWeek() async {
    final next = state.weekStart.add(const Duration(days: 7));
    state = FollowUpCalendarState(weekStart: next, loading: true);
    final items = await _service.fetchForWeek(next);
    if (mounted) {
      state = FollowUpCalendarState(weekStart: next, followUps: items);
    }
  }

  Future<void> prevWeek() async {
    final prev = state.weekStart.subtract(const Duration(days: 7));
    state = FollowUpCalendarState(weekStart: prev, loading: true);
    final items = await _service.fetchForWeek(prev);
    if (mounted) {
      state = FollowUpCalendarState(weekStart: prev, followUps: items);
    }
  }

  Future<void> markDone(String id) async {
    await _service.markDone(id);
    if (mounted) {
      state = FollowUpCalendarState(
        weekStart: state.weekStart,
        followUps: state.followUps.where((f) => f.id != id).toList(),
      );
    }
  }

  Future<void> markSkipped(String id) async {
    await _service.markSkipped(id);
    if (mounted) {
      state = FollowUpCalendarState(
        weekStart: state.weekStart,
        followUps: state.followUps.where((f) => f.id != id).toList(),
      );
    }
  }
}

DateTime _weekStartOf(DateTime date) {
  final weekday = date.weekday; // 1=Mon … 7=Sun
  return DateTime(date.year, date.month, date.day)
      .subtract(Duration(days: weekday - 1));
}

/// Reference "now" used to pick the calendar's initial week. Overridable in
/// tests so the week math is deterministic regardless of the real date.
final followUpCalendarClockProvider = Provider<DateTime>((_) => DateTime.now());

final followUpCalendarProvider = StateNotifierProvider.autoDispose<
    FollowUpCalendarNotifier, FollowUpCalendarState>((ref) {
  final svc = ref.watch(followUpsServiceProvider);
  final weekStart = _weekStartOf(ref.watch(followUpCalendarClockProvider));
  return FollowUpCalendarNotifier(svc, weekStart)..load();
});
