import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Reads the phone's timezone as an IANA name such as `Asia/Manila`, or null
/// when it cannot be read.
typedef ReadTimezone = Future<String?> Function();

/// Tells the server which timezone this household's phone is in, so days
/// (a quest's date, streaks, the daily and weekly limits) end at local
/// midnight rather than at midnight UTC.
///
/// Sent once per sign-in and once when the app reopens a stored session.
/// When the timezone cannot be read, nothing is sent and the household keeps
/// what it has, which starts as Asia/Manila. Free of Flutter imports, so it
/// runs under plain Dart against the real API.
class TimezoneReporter {
  const TimezoneReporter({required this.api, required this.readTimezone});

  final ApiClient api;
  final ReadTimezone readTimezone;

  /// Returns the timezone the server stored, or null when nothing was sent or
  /// the server could not be reached. Never throws: a timezone is a detail,
  /// not a reason to fail a sign-in.
  Future<String?> report() async {
    final String? timezone;
    try {
      timezone = (await readTimezone())?.trim();
    } catch (_) {
      return null;
    }
    if (timezone == null || timezone.isEmpty) return null;

    try {
      final body = await api.patch('/me/timezone', body: {'timezone': timezone});
      return body['timezone'] as String?;
    } on ApiException {
      return null;
    }
  }
}
