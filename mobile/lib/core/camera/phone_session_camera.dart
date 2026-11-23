import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../quest_session/frame_prep.dart';
import 'session_camera.dart';

/// The phone's own camera for a quest session: back to begin with, flipped
/// to the front by the child. No audio is asked for, ever: the microphone
/// permission stays out of the app.
class PhoneSessionCamera implements SessionCamera {
  PhoneSessionCamera({this.front = false});

  /// Which way it faces now.
  bool front;

  CameraController? _controller;
  void Function(YuvFrame frame)? _onFrame;

  @override
  String get label => front ? 'phone_front' : 'phone_back';

  @override
  bool get canFlip => true;

  @override
  bool get isOpen => _controller?.value.isInitialized ?? false;

  Future<CameraDescription> _lens() async {
    final cameras = await availableCameras().timeout(const Duration(seconds: 10));
    if (cameras.isEmpty) throw CameraException('NoCamera', 'This phone has no camera.');
    final wanted = front ? CameraLensDirection.front : CameraLensDirection.back;
    return cameras.firstWhere((c) => c.lensDirection == wanted, orElse: () => cameras.first);
  }

  @override
  Future<void> open() async {
    final controller = CameraController(
      await _lens(),
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
  Future<void> flip() async {
    final controller = _controller;
    if (controller == null) return;
    final streaming = _onFrame;
    if (controller.value.isStreamingImages) await controller.stopImageStream();
    front = !front;
    await controller.setDescription(await _lens());
    if (streaming != null) await startFrames(streaming);
  }

  @override
  Future<void> startFrames(void Function(YuvFrame frame) onFrame) async {
    final controller = _controller;
    if (controller == null || controller.value.isStreamingImages) return;
    _onFrame = onFrame;
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
    _onFrame = null;
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
    _onFrame = null;
    await controller?.dispose();
  }
}
