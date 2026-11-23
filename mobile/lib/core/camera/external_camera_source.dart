import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../models/camera.dart';
import 'camera_source.dart';
import 'phone_session_camera.dart';
import 'session_camera.dart';

/// Answered by MainActivity.
const _cameras = MethodChannel('com.chorequest/cameras');
const _changes = EventChannel('com.chorequest/camera-changes');

/// USB cameras (DV-8): whatever the camera plugin lists as external, which
/// only some phones expose. Listed again whenever Android says a USB device
/// or a camera came or went.
///
/// Keyed by position, usb-1 for the first: Android may give a camera a new
/// id each time it is plugged in, and a home rarely has more than one, so
/// the same camera plugged back in keeps the key its quests were scheduled
/// with.
class ExternalCameraSource implements QuestCameraSource {
  ExternalCameraSource({
    Future<List<CameraDescription>> Function()? cameras,
    Future<bool?> Function()? supported,
  })  : _list = cameras ?? availableCameras,
        _supported = supported ?? _askSupported;

  final Future<List<CameraDescription>> Function() _list;
  final Future<bool?> Function() _supported;

  static Future<bool?> _askSupported() async {
    try {
      return await _cameras.invokeMethod<bool>('usbCameraSupport');
    } catch (_) {
      // No handler (a test, or a platform without one).
      return null;
    }
  }

  /// Whether this phone can use USB cameras at all, or null where it cannot
  /// say. Many phones cannot, and the app says so rather than showing
  /// nothing.
  Future<bool?> supported() => _supported();

  @override
  CameraKind get kind => CameraKind.external;

  @override
  Future<List<ReportedCamera>> list() async {
    final usb = externalOnly(await _list());
    return [
      for (var i = 0; i < usb.length; i++)
        ReportedCamera(
          key: 'usb-${i + 1}',
          kind: CameraKind.external,
          label: usb.length == 1 ? 'USB camera' : 'USB camera ${i + 1}',
          connected: true,
        ),
    ];
  }

  @override
  Stream<void> get changes async* {
    // Only where MainActivity answers; listening with nobody there reports
    // an error instead of staying quiet.
    if (await supported() == null) return;
    yield* _changes.receiveBroadcastStream().map((_) {});
  }

  @override
  SessionCamera open(String key) => ExternalSessionCamera(int.tryParse(key.replaceFirst('usb-', '')) ?? 1);

  /// The external cameras, in a steady order.
  static List<CameraDescription> externalOnly(List<CameraDescription> all) =>
      [for (final camera in all) if (camera.lensDirection == CameraLensDirection.external) camera]
        ..sort((a, b) => a.name.compareTo(b.name));
}

/// A USB camera for a quest session, opened like the phone's own but with
/// no flip.
class ExternalSessionCamera extends PhoneSessionCamera {
  ExternalSessionCamera(this.position);

  /// 1 for the first USB camera.
  final int position;

  @override
  String get label => 'external';

  @override
  bool get canFlip => false;

  @override
  Future<CameraDescription> lens() async {
    final usb = ExternalCameraSource.externalOnly(await availableCameras().timeout(const Duration(seconds: 10)));
    if (usb.length < position) throw CameraException('NoCamera', 'The USB camera is not plugged in.');
    return usb[position - 1];
  }

  @override
  Future<void> flip() async {}
}
