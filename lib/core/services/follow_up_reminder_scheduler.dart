import 'follow_up_reminder_planner.dart';
import 'notification_id_registry.dart';

/// Serializes reminder syncs and applies the plan/reconcile against the OS.
///
/// The OS pending-notification set is the source of truth. Concurrent [sync]
/// calls coalesce: if one is running, the latest leads are remembered and one
/// more pass runs when it finishes. Dart's single-threaded event loop makes the
/// in-flight guard sufficient — there is no true parallelism to protect against.
/// Reconciliation is best-effort — if an OS callback throws, the sync future
/// completes with that error and the OS is left partially reconciled; the next
/// [sync] self-heals because it re-reads the OS pending set.
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
  List<Map<String, dynamic>> _leads = <Map<String, dynamic>>[];

  /// Reconciles the OS reminder set against [leads]. [leads] MUST be the
  /// complete desired set: reconcile cancels any pending reminder whose lead is
  /// not present, so passing a subset will silently cancel the rest. Concurrent
  /// calls coalesce last-set-wins — never race a subset against the full set.
  ///
  /// Secondary callers that arrive mid-flight await the entire drain, including
  /// the extra pass caused by their own leads.
  Future<void> sync(List<Map<String, dynamic>> leads) {
    _leads = List.of(leads);
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
