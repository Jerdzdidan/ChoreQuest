import 'package:flutter/widgets.dart';

import '../quest_session/frame_prep.dart';

/// The camera a quest session watches through (LS-2): the phone's back
/// camera, worn on a head or chest strap so it sees the child's hands
/// (CAM-3). It does not flip: the first-person view is the back camera.
abstract class SessionCamera {
  /// What the evidence calls it: phone_back, or phone_front on a phone
  /// with no back camera.
  String get label;

  /// Whether this is the back camera. False only on a phone that has none,
  /// where the quest falls back to the Before and After photos.
  bool get isBack;

  bool get isOpen;

  Future<void> open();

  /// The live picture.
  Widget preview();

  /// Every frame from now until [stopFrames], as fast as the camera gives
  /// them; the caller decides which to keep.
  Future<void> startFrames(void Function(YuvFrame frame) onFrame);

  Future<void> stopFrames();

  /// A still, saved to the app's cache, never the gallery. Its path.
  Future<String> takeStill();

  Future<void> close();
}
