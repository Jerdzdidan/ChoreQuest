import '../../shared/ringtones.dart';
import '../models/chore.dart';
import '../schedule/next_alarm.dart';

/// One quest's alarm, as the phone arms it.
class QuestAlarm {
  const QuestAlarm({
    required this.assignmentId,
    required this.at,
    required this.choreName,
    required this.ringtoneAsset,
  });

  /// The alarm's id is the assignment's, so a quest has one alarm at a time.
  final int assignmentId;
  final DateTime at;
  final String choreName;

  /// A bundled sound, the same file the parent previewed.
  final String ringtoneAsset;
}

/// What the alarm service asks of the alarm plugin, so the rules can be
/// checked without a phone.
abstract class AlarmBackend {
  Future<bool> set(QuestAlarm alarm);

  /// Takes the alarm away, ringing or not.
  Future<bool> remove(int assignmentId);

  Future<Set<int>> scheduledIds();

  Future<bool> isRinging(int assignmentId);

  /// The ids ringing now, as they change.
  Stream<Set<int>> get ringing;
}

/// Arms, re-arms and stops quest alarms on the child's phone (DV-4).
///
/// Every quest's next ring is worked out by nextAlarm, on the phone's clock,
/// which is the household's clock when the phone reported its timezone
/// (TZ2). A daily quest is armed for its next weekday again whenever its
/// alarm is stopped, and every alarm is re-armed at each app start and sync.
///
/// [stop] is the only way a ringing alarm goes quiet. It is called from one
/// place: the live session's first matching movement (or, with no model,
/// Start and the Before photo) (DV-6), and the safety net's timeout and
/// grown-up stop (DV-7). [cancel] and [rearmAll] never touch an alarm that
/// is ringing. The one other way is [silenceOffSchedule], for an alarm whose
/// quest is gone, which has no session to stop it.
class QuestAlarmService {
  QuestAlarmService(this.backend, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AlarmBackend backend;
  final DateTime Function() _now;

  QuestAlarm? alarmFor(Assignment assignment, {DateTime? after}) {
    final at = nextAlarm(assignment.schedule, after ?? _now(), active: assignment.isActive);
    if (at == null) return null;
    return QuestAlarm(
      assignmentId: assignment.id,
      at: at,
      choreName: assignment.chore.name,
      ringtoneAsset: ringtoneFor(assignment.ringtoneKey).asset,
    );
  }

  /// Arms the quest's next ring, or takes its alarm away when it has none.
  /// Returns when it will ring.
  Future<DateTime?> arm(Assignment assignment, {DateTime? after}) async {
    if (await backend.isRinging(assignment.id)) return null;
    final alarm = alarmFor(assignment, after: after);
    if (alarm == null) {
      await cancel(assignment.id);
      return null;
    }
    await backend.set(alarm);
    return alarm.at;
  }

  /// Takes away a quest's alarm that has not started ringing.
  Future<void> cancel(int assignmentId) async {
    if (await backend.isRinging(assignmentId)) return;
    if ((await backend.scheduledIds()).contains(assignmentId)) await backend.remove(assignmentId);
  }

  /// Arms every quest on the schedule and takes away alarms for quests no
  /// longer on it, leaving a ringing one alone.
  Future<void> rearmAll(List<Assignment> assignments) async {
    final wanted = {for (final a in assignments) a.id};
    for (final id in await backend.scheduledIds()) {
      if (!wanted.contains(id)) await cancel(id);
    }
    for (final assignment in assignments) {
      await arm(assignment);
    }
  }

  /// Silences a ringing alarm and arms the quest's next ring. See the class
  /// note for who may call this.
  Future<void> stop(Assignment assignment) async {
    await backend.remove(assignment.id);
    // After this minute, so today's ring is not armed again.
    await arm(assignment, after: _now().add(const Duration(minutes: 1)));
  }

  /// Silences an alarm whose quest is not on [schedule]: the parent removed
  /// or paused it while it rang, so there is no quest to start and nothing
  /// else could stop it. Does nothing to a quest that is on it.
  Future<void> silenceOffSchedule(int assignmentId, List<Assignment> schedule) async {
    if (schedule.any((a) => a.id == assignmentId)) return;
    await backend.remove(assignmentId);
  }
}
