/// Dates and times as the API writes them.
///
/// The server sends `YYYY-MM-DD` for dates and `HH:MM:SS` for times of day, and
/// accepts `HH:MM` when writing. Keeping the conversions here means no screen
/// ever builds one of these strings by hand.
library;

String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Reads a date-only string as a calendar date, with no time-of-day attached
/// that could shift it onto a neighbouring day.
DateTime parseApiDate(String raw) {
  final parsed = DateTime.parse(raw);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// A time of day with no date, such as a chore's "finish by" time.
///
/// A plain Dart type rather than Flutter's TimeOfDay, so the models stay
/// usable outside the Flutter runtime.
class ClockTime {
  const ClockTime(this.hour, this.minute);

  final int hour;
  final int minute;

  /// Accepts "17:30" or "17:30:00". Anything else, including null, is null.
  static ClockTime? tryParse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return ClockTime(hour, minute);
  }

  /// The form the API accepts when writing.
  String get wire =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}
