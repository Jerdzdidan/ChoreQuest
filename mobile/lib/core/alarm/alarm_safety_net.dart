import '../models/chore.dart';
import 'quest_alarm_service.dart';

/// The one place, beside the live session, that may silence a ringing
/// alarm (DV-7): if the camera or the model ever fails, an alarm that
/// nothing could stop would leave a child's phone ringing.
///
/// - After the longest ring (the model config's max_ring_minutes) it stops
///   by itself; the quest counts as missed, with no penalty, and the parent
///   is told.
/// - A grown-up can stop it with their own account password, checked by the
///   server, which records it for the parent to see.
///
/// Both report to the server, so neither can be used quietly.
class AlarmSafetyNet {
  AlarmSafetyNet({
    required this.alarms,
    required this.report,
    required this.override,
  });

  final QuestAlarmService alarms;

  /// POST /my/alarm-events: timed_out or camera_missing.
  final Future<void> Function(String kind, int assignmentId) report;

  /// POST /alarm/override with the grown-up's password; throws when the
  /// server refuses it.
  final Future<void> Function(String password, int assignmentId) override;

  /// How long an alarm that started at [ringingSince] has left before it
  /// stops by itself, never below nothing.
  static Duration remaining(DateTime ringingSince, int maxRingMinutes, DateTime now) {
    final left = ringingSince.add(Duration(minutes: maxRingMinutes)).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// The alarm rang its longest: quiet, missed, and the parent told.
  Future<void> timedOut(Assignment assignment) async {
    await alarms.stop(assignment);
    try {
      await report('timed_out', assignment.id);
    } catch (_) {
      // The alarm is quiet either way; the report is a courtesy that can fail.
    }
  }

  /// A grown-up's stop: only once the server has accepted the password. A
  /// wrong one leaves the alarm ringing and throws.
  Future<void> grownUpStop(Assignment assignment, String password) async {
    await override(password, assignment.id);
    await alarms.stop(assignment);
  }
}
