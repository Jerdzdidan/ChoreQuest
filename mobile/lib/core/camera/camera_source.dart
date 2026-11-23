import 'dart:async';

import '../models/camera.dart';
import '../models/chore.dart';
import 'session_camera.dart';

/// Where the cameras a quest can be watched through come from (DV-8), one
/// kind each: the phone's own front and back, USB cameras the phone exposes,
/// and network cameras added by address (DV-11). Each lists what it has
/// connected right now, says when that may have changed, and opens one for
/// a session.
abstract class QuestCameraSource {
  CameraKind get kind;

  /// Its cameras now, each saying whether it is connected.
  Future<List<ReportedCamera>> list();

  /// An event whenever [list] may have changed, such as a USB camera
  /// plugged in or out. Empty for a kind that never changes.
  Stream<void> get changes;

  /// A session camera for one of its cameras, by its key.
  SessionCamera open(String key);
}

/// The camera a session watches through, and whether it is the phone's own
/// because the scheduled one was missing (DV-12).
class CameraChoice {
  const CameraChoice(this.camera, {this.fellBack = false});

  final SessionCamera camera;
  final bool fellBack;
}

/// Picks a session's camera (DV-12): the third-party camera the parent
/// scheduled if it is connected now, and otherwise the phone's own, so a
/// child is never stuck unable to start. A missing camera is reported for
/// the parent, and the session tells the child in a friendly sentence.
class CameraChooser {
  CameraChooser({
    required this.thirdParty,
    required this.phone,
    required this.onMissing,
  });

  /// USB and network cameras.
  final List<QuestCameraSource> thirdParty;

  /// The phone's own camera for a quest.
  final SessionCamera Function(Assignment assignment) phone;

  /// POST /my/alarm-events camera_missing.
  final Future<void> Function(Assignment assignment) onMissing;

  Future<CameraChoice> choose(Assignment assignment) async {
    if (assignment.cameraSource != CameraSource.external) return CameraChoice(phone(assignment));
    final wanted = assignment.cameraDeviceId;
    if (wanted != null) {
      for (final source in thirdParty) {
        try {
          final cameras = await source.list();
          if (cameras.any((c) => c.key == wanted && c.connected)) return CameraChoice(source.open(wanted));
        } catch (_) {
          // This kind cannot say: try the next, then the phone.
        }
      }
    }
    unawaited(onMissing(assignment).catchError((_) {}));
    return CameraChoice(phone(assignment), fellBack: true);
  }
}

/// One signal from any of [streams]: what the camera reporter listens to,
/// whichever kind of camera changed.
Stream<void> anyChange(Iterable<Stream<void>> streams) {
  final listening = <StreamSubscription<void>>[];
  late final StreamController<void> out;
  out = StreamController<void>(
    onListen: () {
      for (final stream in streams) {
        listening.add(stream.listen(out.add, onError: (_) {}));
      }
    },
    // All at once, so each one's timers stop now rather than after the
    // others have finished.
    onCancel: () async {
      final cancelling = [for (final subscription in listening) subscription.cancel()];
      listening.clear();
      await Future.wait(cancelling);
    },
  );
  return out.stream;
}
