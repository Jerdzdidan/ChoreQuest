import 'package:camera/camera.dart';

import '../models/camera.dart';
import 'camera_source.dart';
import 'phone_session_camera.dart';
import 'session_camera.dart';

/// The phone's own front and back cameras (DV-8): always there, and the
/// child flips between them in a session.
class PhoneCameraSource implements QuestCameraSource {
  PhoneCameraSource({Future<List<CameraDescription>> Function()? cameras}) : _cameras = cameras ?? availableCameras;

  final Future<List<CameraDescription>> Function() _cameras;

  @override
  CameraKind get kind => CameraKind.phone;

  @override
  Future<List<ReportedCamera>> list() async {
    final lenses = {for (final camera in await _cameras()) camera.lensDirection};
    return [
      if (lenses.contains(CameraLensDirection.back))
        const ReportedCamera(key: 'back', kind: CameraKind.phone, label: 'Back camera', connected: true),
      if (lenses.contains(CameraLensDirection.front))
        const ReportedCamera(key: 'front', kind: CameraKind.phone, label: 'Front camera', connected: true),
    ];
  }

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  SessionCamera open(String key) => PhoneSessionCamera(front: key == 'front');
}
