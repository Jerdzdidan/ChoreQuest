import 'package:alarm/alarm.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../alarm/plugin_alarm_backend.dart';
import '../alarm/quest_alarm_service.dart';
import '../api/api_client.dart';
import '../app_files.dart';
import '../session/session.dart';
import '../session/session_store.dart';
import 'schedule_store.dart';
import 'schedule_sync.dart';

const _task = 'chorequest.schedule-sync';

/// Where the schedule is saved, in the app's private files.
const scheduleFileName = 'schedule.json';

/// Runs in a background isolate about every 15 minutes, the most Android
/// allows (DV-3): with the app closed, a schedule the parent changed is
/// fetched and armed. Only on a child's phone; nothing happens otherwise.
@pragma('vm:entry-point')
void scheduleSyncDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      final session = await SessionStore().readSession();
      if (session is! ChildSession) return true;
      final api = ApiClient(readToken: () async => session.token);
      final base = await getApplicationSupportDirectory();
      await Alarm.init();
      await ScheduleSync(
        fetch: () => api.get('/my/schedule'),
        store: ScheduleStore(appFile(base, scheduleFileName)),
        alarms: QuestAlarmService(const PluginAlarmBackend()),
      ).sync();
    } catch (_) {
      // The next run tries again; the saved schedule stays armed meanwhile.
    }
    return true;
  });
}

/// Starts the 15-minute background sync. Registering again changes nothing.
Future<void> startBackgroundScheduleSync() async {
  await Workmanager().initialize(scheduleSyncDispatcher);
  await Workmanager().registerPeriodicTask(
    _task,
    _task,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
