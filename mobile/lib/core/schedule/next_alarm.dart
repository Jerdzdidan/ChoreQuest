import '../models/chore.dart';

/// When a quest's alarm next rings at or after [from], on the same clock as
/// [from] (the household's local time), or null when it never will: no
/// alarm time, the alarm switched off, the quest paused, or a one-time quest
/// whose moment has passed.
///
/// Pure: the moment is passed in, never read from a clock, so the parent's
/// Board and the child's phone (DV-4) work it out the same way and any case
/// can be checked by hand.
DateTime? nextAlarm(QuestSchedule schedule, DateTime from, {bool active = true}) {
  final time = schedule.alarmTime;
  if (!active || !schedule.alarmEnabled || time == null) return null;

  if (schedule.recurrence == Recurrence.once) {
    final day = schedule.scheduledDate;
    if (day == null) return null;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    return at.isBefore(from) ? null : at;
  }

  // Today and the next seven days cover every weekday at least once, even
  // when today's alarm has already gone.
  for (var offset = 0; offset <= 7; offset++) {
    final day = DateTime(from.year, from.month, from.day + offset);
    if (!schedule.repeatsOn(day.weekday)) continue;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (!at.isBefore(from)) return at;
  }
  return null;
}

/// The assignment whose alarm rings soonest at or after [from], and when;
/// null when none of them will ring. Two ringing at once go in the order
/// given.
(Assignment, DateTime)? nextQuestAlarm(Iterable<Assignment> assignments, DateTime from) {
  (Assignment, DateTime)? soonest;
  for (final assignment in assignments) {
    final at = nextAlarm(assignment.schedule, from, active: assignment.isActive);
    if (at != null && (soonest == null || at.isBefore(soonest.$2))) soonest = (assignment, at);
  }
  return soonest;
}
