import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alarm/alarm_safety_net.dart';
import '../../core/alarm/plugin_alarm_backend.dart';
import '../../core/alarm/quest_alarm_service.dart';
import '../../core/app_files.dart';
import '../../core/camera/phone_session_camera.dart';
import '../../core/camera/session_camera.dart';
import '../../core/device/phone_readiness.dart';
import '../../core/device/platform_readiness_probe.dart';
import '../../core/models/chore.dart';
import '../../core/quest_session/chore_detector.dart';
import '../../core/quest_session/fake_detector.dart';
import '../../core/quest_session/model_config.dart';
import '../../core/quest_session/no_model_detector.dart';
import '../../core/schedule/background_sync.dart';
import '../../core/schedule/schedule_store.dart';
import '../../core/schedule/schedule_sync.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import 'child_providers.dart';
import 'quest_session_controller.dart';
import 'submission_sender.dart';
import 'upload_sync.dart';

/// The camera a session uses for an assignment: the phone's own for now;
/// a scheduled third-party camera joins with DV-8 and DV-11.
final sessionCameraProvider = Provider<SessionCamera Function(Assignment assignment)>(
  (ref) => (_) => PhoneSessionCamera(),
);

/// The movement detector a session watches with. Debug builds get the fake
/// one (LS-4); a release build, until the trained model is bundled (LS-5),
/// gets none and runs every session manual.
final choreDetectorProvider = Provider<ChoreDetector Function()>(
  (ref) => () => kDebugMode ? FakeDetector() : const NoModelDetector(),
);

/// The model config, fetched at app open and kept for offline (BE-6).
final modelConfigProvider = FutureProvider<ModelConfig>((ref) {
  final store = ModelConfigStore(
    api: ref.watch(apiClientProvider),
    file: appFile(ref.watch(appFilesProvider), 'model_config.json'),
  );
  return store.load();
});

/// The quest alarms on this phone (DV-4).
final questAlarmServiceProvider = Provider<QuestAlarmService>(
  (ref) => QuestAlarmService(const PluginAlarmBackend()),
);

/// Stops a quest's ringing alarm and arms its next ring. The live session's
/// first matching movement is its only caller (DV-6), with the safety net
/// beside it (DV-7).
final alarmStopperProvider = Provider<void Function(Assignment assignment)>((ref) {
  final alarms = ref.watch(questAlarmServiceProvider);
  return (assignment) => alarms.stop(assignment).catchError((_) {});
});

/// The safety net beside the session (DV-7): the longest ring and the
/// grown-up stop, both reported to the parent.
final alarmSafetyNetProvider = Provider<AlarmSafetyNet>((ref) {
  final api = ref.watch(childApiProvider);
  return AlarmSafetyNet(
    alarms: ref.watch(questAlarmServiceProvider),
    report: api.reportAlarmEvent,
    override: api.alarmOverride,
  );
});

/// The schedule saved on this phone (DV-2).
final scheduleStoreProvider = Provider<ScheduleStore>(
  (ref) => ScheduleStore(appFile(ref.watch(appFilesProvider), scheduleFileName)),
);

/// What this phone's alarms need, read from Android (DV-1).
final readinessProbeProvider = Provider<ReadinessProbe>((ref) => const PlatformReadinessProbe());

/// Checks the phone, keeps the result and reports it with the last schedule
/// sync (DV-10).
final phoneReadinessProvider = Provider<PhoneReadinessService>((ref) {
  final schedule = ref.watch(scheduleStoreProvider);
  return PhoneReadinessService(
    probe: ref.watch(readinessProbeProvider),
    store: ReadinessStore(appFile(ref.watch(appFilesProvider), 'phone_readiness.json')),
    report: ref.watch(childApiProvider).reportDeviceStatus,
    lastSync: () async => (await schedule.load())?.fetchedAt,
  );
});

/// Fetches the schedule, saves it and arms it (DV-3), for the signed-in
/// child.
final scheduleSyncProvider = Provider<ScheduleSync>(
  (ref) => ScheduleSync(
    fetch: ref.watch(childApiProvider).mySchedule,
    store: ref.watch(scheduleStoreProvider),
    alarms: ref.watch(questAlarmServiceProvider),
  ),
);

/// Hands a finished session to the upload queue and tries to send it at once
/// (LS-9), under the signed-in child's own sign-in. Saved first, so a session
/// that cannot go now is not lost.
final sessionSenderProvider = Provider<Future<SendOutcome> Function(SessionPackage package)>((ref) {
  final me = switch (ref.watch(sessionProvider)) {
    AsyncData(value: final ChildSession s) => s,
    _ => null,
  };
  return (package) async {
    if (me == null) return const Refused('Sign in again to send this quest.');
    final queue = ref.read(uploadQueueProvider);
    final sync = ref.read(uploadSyncProvider(me.token));
    final upload = await queue.enqueueSession(
      clientToken: package.clientToken,
      childId: me.id,
      assignmentId: package.assignment.id,
      choreName: package.assignment.chore.name,
      sourceBeforePath: package.beforePath,
      sourceAfterPath: package.afterPath,
      evidence: package.evidence,
    );
    final result = await sync.send(upload);
    return switch (result.outcome) {
      UploadOutcome.sent => Sent(result.submission!),
      UploadOutcome.refused => Refused(result.message ?? 'This quest was not accepted.'),
      UploadOutcome.waiting => Queued(result.message ?? 'No connection.'),
    };
  };
});
