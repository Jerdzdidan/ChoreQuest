import 'dart:async';

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/foundation.dart';

import '../../core/camera/session_camera.dart';
import '../../core/models/chore.dart';
import '../../core/quest_session/chore_detector.dart';
import '../../core/quest_session/done_gate.dart';
import '../../core/quest_session/evidence.dart';
import '../../core/quest_session/frame_prep.dart';
import '../../core/quest_session/quest_session.dart';
import '../../core/uploads/client_token.dart';
import 'submission_sender.dart';

/// A finished session, ready for the upload queue (LS-9).
class SessionPackage {
  const SessionPackage({
    required this.clientToken,
    required this.assignment,
    required this.beforePath,
    required this.afterPath,
    required this.evidence,
  });

  final String clientToken;
  final Assignment assignment;
  final String beforePath;
  final String afterPath;
  final Map<String, Object?> evidence;
}

/// Why the camera cannot be used, in words a child's grown-up can act on.
enum CameraProblem { denied, noCamera, failed }

/// Runs one live quest session (LS-2): opens the camera, takes the Before
/// photo once the picture is steady (LS-7), feeds frames to the detector at
/// about four a second (LS-3), stops the alarm at the first matching
/// movement (DV-6), takes the After photo at Done, and hands the session to
/// the upload queue (LS-9). A chore with no model, or a phone where the
/// model cannot run, goes the same way without the detector (LS-11).
///
/// No widgets in here: the screen draws what this holds, and a test can run
/// it with a pretend camera and the fake detector.
class QuestSessionController extends ChangeNotifier {
  QuestSessionController({
    required this.assignment,
    required this.camera,
    required this.detector,
    required GateThresholds thresholds,
    required this.sendPackage,
    required this.onStopAlarm,
    this.prep,
    this.phoneModel,
    this.strapped = true,
    DateTime Function()? now,
    this.steadyTimeout = const Duration(seconds: 6),
    this.frameInterval = const Duration(milliseconds: 250),
  }) : _now = now ?? DateTime.now {
    final chore = assignment.chore;
    final motion = chore.verificationMode == VerificationMode.motion && chore.modelClass != null;
    session = QuestSession(
      mode: motion ? CheckMode.motion : CheckMode.manual,
      thresholds: thresholds,
      now: _now,
      onEvent: _onEvent,
    );
  }

  final Assignment assignment;
  final SessionCamera camera;
  final ChoreDetector detector;
  final Future<SendOutcome> Function(SessionPackage package) sendPackage;

  /// Stops the alarm. Called once, at the first matching movement or, with
  /// no model, once the Before photo is taken (DV-6).
  final void Function() onStopAlarm;

  /// Turns frames into model input off the UI thread; null runs no frames
  /// through the model at all, as with the fake detector, which needs none.
  final FramePrepWorker? prep;
  final String? phoneModel;

  /// The child said the phone is strapped on (CAM-3). Without a strap the
  /// model may not see the chore, so a quest it checks goes manual and the
  /// grown-up judges from the Before and After photos.
  final bool strapped;

  /// The longest to wait for a steady picture before taking Before anyway.
  final Duration steadyTimeout;

  /// About four frames a second reach the model; the rest are dropped.
  final Duration frameInterval;

  final DateTime Function() _now;

  late final QuestSession session;
  final String clientToken = newClientToken();

  String? beforePath;
  String? afterPath;
  double progress = 0;
  CameraProblem? problem;
  SendOutcome? outcome;

  /// A step that the screen should not interrupt is running.
  bool busy = false;

  final _clock = Stopwatch();
  Duration? _lastFrame;
  Float32List? _beforeInput;
  Float32List? _latestInput;
  StreamSubscription<DetectorSignal>? _signals;
  var _paused = false;
  var _disposed = false;

  SessionState get state => session.state;

  /// Whether the frame stream is meant to be running: from Before to Done
  /// with a model watching.
  bool get _watching =>
      session.mode == CheckMode.motion &&
      (state == SessionState.waitingForMovement || state == SessionState.active || state == SessionState.doneAvailable);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _onEvent(SessionEvent event) {
    switch (event) {
      case StopAlarm():
        onStopAlarm();
      case SessionProgress(:final fraction):
        progress = fraction;
      case StateChanged():
        break;
    }
    _changed();
  }

  /// The child tapped Start the quest.
  Future<void> begin() async {
    _clock.start();
    session.start();
    if (session.mode == CheckMode.motion && !detector.available) session.goManual();
    if (session.mode == CheckMode.motion && !strapped) session.goManual(ManualReason.noStrap);
    _changed();
    if (!await _open()) return;
    // Only the back camera, on a strap, sees the child's hands.
    if (session.mode == CheckMode.motion && !camera.isBack) session.goManual(ManualReason.noBackCamera);
    await _captureBefore();
  }

  Future<bool> _open() async {
    try {
      await camera.open();
      problem = null;
      _changed();
      return true;
    } on CameraException catch (e) {
      problem = e.code == 'CameraAccessDenied' ? CameraProblem.denied : (e.code == 'NoCamera' ? CameraProblem.noCamera : CameraProblem.failed);
    } catch (_) {
      problem = CameraProblem.failed;
    }
    _changed();
    return false;
  }

  /// Try the camera again after a problem; the session carries on where it
  /// was.
  Future<void> retryCamera() async {
    if (!await _open()) return;
    if (state == SessionState.starting) {
      await _captureBefore();
    } else if (_watching) {
      await camera.startFrames(_onFrame);
    }
  }

  /// Waits for a steady picture, up to [steadyTimeout], then takes Before
  /// with the frame stream stopped, as the camera requires.
  Future<void> _captureBefore() async {
    final steady = SteadyWatch();
    final ready = Completer<void>();
    final waitStarted = _clock.elapsed;
    await camera.startFrames((frame) {
      if (ready.isCompleted) return;
      final at = _clock.elapsed;
      if (steady.add(lumaThumbnail(frame), at) || at - waitStarted >= steadyTimeout) ready.complete();
    });
    // A camera that sends no frames still gets its Before photo.
    await Future.any([ready.future, Future<void>.delayed(steadyTimeout)]);
    if (_disposed || _paused) return;
    await camera.stopFrames();
    try {
      beforePath = await camera.takeStill();
    } on Object {
      problem = CameraProblem.failed;
      _changed();
      return;
    }
    session.beforeCaptured();
    _changed();
    if (session.mode == CheckMode.motion) await _watch();
  }

  Future<void> _watch() async {
    await detector.start(targetClass: assignment.chore.modelClass!);
    _signals = detector.signals.listen((signal) {
      if (!_disposed) session.signal(signal);
    });
    await camera.startFrames(_onFrame);
  }

  void _onFrame(YuvFrame frame) {
    final worker = prep;
    if (worker == null || worker.busy) return;
    final at = _clock.elapsed;
    final last = _lastFrame;
    if (last != null && at - last < frameInterval) return;
    _lastFrame = at;
    unawaited(worker.prepare(frame).then((input) {
      if (input == null || _disposed) return;
      _beforeInput ??= input;
      _latestInput = input;
      detector.addFrame(input, at);
    }));
  }

  /// The child tapped Done: the frames stop and the After photo is taken.
  Future<void> done() async {
    if (!session.showsDone || busy) return;
    busy = true;
    session.done();
    _changed();
    try {
      await camera.stopFrames();
      afterPath = await camera.takeStill();
      session.afterCaptured();
    } on Object {
      problem = CameraProblem.failed;
    } finally {
      busy = false;
      _changed();
    }
  }

  /// From the review: take After again.
  Future<void> retakeAfter() async {
    if (state != SessionState.reviewing || busy) return;
    busy = true;
    session.retakeAfter();
    _changed();
    try {
      afterPath = await camera.takeStill();
      session.afterCaptured();
    } on Object {
      problem = CameraProblem.failed;
    } finally {
      busy = false;
      _changed();
    }
  }

  /// Send to my grown-up: into the upload queue, sent now if it can be.
  /// Nothing is credited until the grown-up approves.
  Future<void> send() async {
    final before = beforePath;
    final after = afterPath;
    if (state != SessionState.reviewing || before == null || after == null || busy) return;
    busy = true;
    session.send();
    _changed();

    final evidence = buildEvidence(
      session: session,
      choreKey: assignment.chore.key,
      modelVersion: detector.version,
      camera: camera.label,
      sceneChangeScore: await _sceneChange(),
      meanModelMs: detector.meanModelMs,
      phoneModel: phoneModel,
    );
    outcome = await sendPackage(SessionPackage(
      clientToken: clientToken,
      assignment: assignment,
      beforePath: before,
      afterPath: after,
      evidence: evidence,
    ));
    if (outcome is Refused) {
      session.fail((outcome! as Refused).message);
    } else {
      session.sent();
    }
    busy = false;
    _changed();
  }

  Future<double?> _sceneChange() async {
    final before = _beforeInput;
    final after = _latestInput;
    if (before == null || after == null || identical(before, after)) return null;
    try {
      return sceneChange(await detector.embed(before), await detector.embed(after));
    } catch (_) {
      return null;
    }
  }

  /// The app went to the background: the camera is let go, as Android
  /// expects, and taken back on [resume].
  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    await camera.stopFrames();
    await camera.close();
  }

  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    if (!await _open()) return;
    if (state == SessionState.starting) {
      await _captureBefore();
    } else if (_watching) {
      await camera.startFrames(_onFrame);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_signals?.cancel());
    unawaited(detector.stop());
    unawaited(camera.close());
    prep?.stop();
    super.dispose();
  }
}
