import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_files.dart';
import '../../core/camera/phone_session_camera.dart';
import '../../core/camera/session_camera.dart';
import '../../core/models/chore.dart';
import '../../core/quest_session/chore_detector.dart';
import '../../core/quest_session/fake_detector.dart';
import '../../core/quest_session/model_config.dart';
import '../../core/quest_session/no_model_detector.dart';
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

/// Stops a quest's ringing alarm. Nothing rings yet; the alarm service
/// (DV-4) puts the real stop here, and DV-6 keeps this its only caller.
final alarmStopperProvider = Provider<void Function(Assignment assignment)>(
  (ref) => (_) {},
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
