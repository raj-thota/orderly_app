// Pure follow-up reminder planning. No Flutter, plugin, or IO imports so it
// can be unit-tested in isolation and reasoned about deterministically.

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
  if (value is DateTime) return value.toLocal();
  return DateTime.tryParse(value.toString())?.toLocal();
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
/// no longer planned. Callers must schedule every entry in [toSchedule]; the OS
/// plugin is expected to replace any existing notification with a matching id
/// in place rather than firing a duplicate.
ReminderReconciliation reconcileReminders(
  List<PlannedReminder> planned,
  Set<int> currentPendingIds,
) {
  final plannedIds = planned.map((r) => r.id).toSet();
  final toCancel =
      currentPendingIds.where((id) => !plannedIds.contains(id)).toList();
  return ReminderReconciliation(toSchedule: planned, toCancel: toCancel);
}
