import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../quest_session/frame_prep.dart';
import 'session_camera.dart';

/// The phone's back camera for a quest session (CAM-3), on a strap. A phone
/// with no back camera opens whichever it has, and the session falls back to
/// the Before and After photos. No audio is asked for, ever: the microphone
/// permission stays out of the app.
class PhoneSessionCamera implements SessionCamera {
  CameraController? _controller;
  var _isBack = true;

  @override
  String get label => _isBack ? 'phone_back' : 'phone_front';

  @override
  bool get isBack => _isBack;

  @override
  bool get isOpen => _controller?.value.isInitialized ?? false;

  /// The camera to open: the back one, or the first there is.
  @protected
  Future<CameraDescription> lens() async {
    final cameras = await availableCameras().timeout(const Duration(seconds: 10));
    if (cameras.isEmpty) throw CameraException('NoCamera', 'This phone has no camera.');
    final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
    _isBack = back.isNotEmpty;
    return back.isNotEmpty ? back.first : cameras.first;
  }

  @override
  Future<void> open() async {
    final controller = CameraController(
      await lens(),
      // Medium is plenty for a model that looks at 192 x 192, and keeps a
      // low-end phone cool.
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    _controller = controller;
  }

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(controller);
  }

  @override
  Future<void> startFrames(void Function(YuvFrame frame) onFrame) async {
    final controller = _controller;
    if (controller == null || controller.value.isStreamingImages) return;
    final rotation = controller.description.sensorOrientation;
    await controller.startImageStream((image) {
      if (image.planes.length < 3) return;
      final (y, u, v) = (image.planes[0], image.planes[1], image.planes[2]);
      onFrame(YuvFrame(
        width: image.width,
        height: image.height,
        y: y.bytes,
        u: u.bytes,
        v: v.bytes,
        yRowStride: y.bytesPerRow,
        uvRowStride: u.bytesPerRow,
        uvPixelStride: u.bytesPerPixel ?? 1,
        rotation: rotation,
      ));
    });
  }

  @override
  Future<void> stopFrames() async {
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) await controller.stopImageStream();
  }

  @override
  Future<String> takeStill() async {
    final controller = _controller;
    if (controller == null) throw CameraException('NotOpen', 'The camera is not open.');
    return (await controller.takePicture()).path;
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
