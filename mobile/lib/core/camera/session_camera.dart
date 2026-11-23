import 'package:flutter/widgets.dart';

import '../quest_session/frame_prep.dart';

/// A camera a quest session watches through (LS-2): the phone's own, which
/// the child flips between front and back, or a third-party one (DV-8,
/// DV-11), which does not flip. The session never asks which it is beyond
/// these few calls, so the same detector takes frames from any of them.
abstract class SessionCamera {
  /// What the evidence calls it: phone_back, phone_front, external or
  /// network.
  String get label;

  /// Only the phone's own camera flips; a third-party one shows no button.
  bool get canFlip;

  bool get isOpen;

  Future<void> open();

  /// The live picture.
  Widget preview();

  /// Front to back or back to front, keeping the frame stream going if it
  /// was.
  Future<void> flip();

  /// Every frame from now until [stopFrames], as fast as the camera gives
  /// them; the caller decides which to keep.
  Future<void> startFrames(void Function(YuvFrame frame) onFrame);

  Future<void> stopFrames();

  /// A still, saved to the app's cache, never the gallery. Its path.
  Future<String> takeStill();

  Future<void> close();
}
