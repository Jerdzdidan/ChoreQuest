import '../alarm/quest_alarm_service.dart';
import 'schedule_store.dart';

/// Keeps the alarms on the child's phone in step with the schedule the
/// parent sets (DV-3): fetches it when the app opens or comes back, and from
/// a background task about every 15 minutes, saves it (DV-2), arms what is
/// new and changed, and takes away what was removed.
///
/// Offline, the saved copy is armed again, so a killed app or a day without
/// a connection leaves every alarm in place.
class ScheduleSync {
  ScheduleSync({
    required this.fetch,
    required this.store,
    required this.alarms,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// GET /my/schedule.
  final Future<Map<String, dynamic>> Function() fetch;
  final ScheduleStore store;
  final QuestAlarmService alarms;
  final DateTime Function() _now;

  /// The schedule now armed, from the server or, offline, the saved copy;
  /// null when there has never been one.
  Future<ScheduleSnapshot?> sync() async {
    try {
      await store.save(await fetch(), _now());
    } catch (_) {
      // No connection, or the server was unhappy: arm what was saved.
    }
    final snapshot = await store.load();
    if (snapshot != null) await alarms.rearmAll(snapshot.assignments);
    return snapshot;
  }
}
