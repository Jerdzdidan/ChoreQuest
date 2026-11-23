import 'package:flutter/material.dart';

import '../core/models/api_dates.dart';
import '../core/models/chore.dart';

/// Short weekday names by [DateTime.weekday] number, Monday first.
const weekdayShort = <int, String>{
  DateTime.monday: 'Mon',
  DateTime.tuesday: 'Tue',
  DateTime.wednesday: 'Wed',
  DateTime.thursday: 'Thu',
  DateTime.friday: 'Fri',
  DateTime.saturday: 'Sat',
  DateTime.sunday: 'Sun',
};

const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Every day of the week, Monday to Sunday.
const everyDay = {1, 2, 3, 4, 5, 6, 7};
const weekdays = {1, 2, 3, 4, 5};
const weekend = {6, 7};

/// The days a daily quest repeats on, as a parent would say them: "Every
/// day", "Weekdays", "Weekends", or the days themselves, Monday first.
String repeatText(List<int>? days) {
  final set = days?.toSet() ?? everyDay;
  if (set.containsAll(everyDay)) return 'Every day';
  if (set.length == 5 && set.containsAll(weekdays)) return 'Weekdays';
  if (set.length == 2 && set.containsAll(weekend)) return 'Weekends';
  return [for (final day in everyDay) if (set.contains(day)) weekdayShort[day]].join(' ');
}

/// "Sat 21 Nov": a one-time quest's day, short enough for a list line.
String shortDate(DateTime date) => '${weekdayShort[date.weekday]} ${date.day} ${_monthShort[date.month - 1]}';

String alarmText(ClockTime time, MaterialLocalizations localizations) =>
    localizations.formatTimeOfDay(TimeOfDay(hour: time.hour, minute: time.minute));

/// One line for a quest's schedule in the parent's lists (PS-9), such as
/// "Mon Wed Fri · 4:30 PM · Phone camera" or "Sat 21 Nov · 9:00 AM". A
/// one-time quest names no camera, since it always uses the phone.
String scheduleLine(QuestSchedule schedule, MaterialLocalizations localizations) {
  final date = schedule.scheduledDate;
  final alarm = schedule.alarmTime;
  return [
    if (schedule.recurrence == Recurrence.daily)
      repeatText(schedule.daysOfWeek)
    else
      date == null ? 'One day' : shortDate(date),
    if (alarm != null) alarmText(alarm, localizations),
    if (schedule.recurrence == Recurrence.daily) schedule.cameraSource.label,
  ].join(' · ');
}
