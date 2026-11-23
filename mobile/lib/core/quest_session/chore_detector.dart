/// What the movement detector reports about one moment of a quest session
/// (LS-4): how much the last few seconds look like the assigned chore, and
/// whether there was task-like movement at all.
class DetectorSignal {
  const DetectorSignal({
    required this.at,
    required this.targetProbability,
    required this.activity,
    this.topClass,
  });

  /// When, counted from the moment the session started.
  final Duration at;

  /// The model's probability that the child is doing the assigned chore.
  final double targetProbability;

  /// How much task-like movement there was, 0 (still) to 1.
  final double activity;

  /// The class the model thought most likely, for the evidence; null when
  /// the detector does not say.
  final int? topClass;
}

/// Turns what the camera sees into [DetectorSignal]s for the session.
///
/// The real one (LS-5) runs the CNN on every frame and the LSTM about once a
/// second; the fake one (debug builds) makes signals up, so every other part
/// of the session can be built and tried before a model exists.
abstract class ChoreDetector {
  /// False when no model could be loaded: the session then runs manual and
  /// the parent is told (LS-5).
  bool get available;

  /// The model's name and version, for the evidence.
  String get version;

  /// The mean time the model took per frame so far, in milliseconds, for the
  /// evidence; null when it does not measure.
  int? get meanModelMs;

  /// Whether it wants camera frames at all. The fake detector makes its
  /// signals up and needs none, so no frame is prepared for it.
  bool get needsFrames;

  /// One signal at a time, in order, until [stop].
  Stream<DetectorSignal> get signals;

  /// Starts watching for the chore with this class.
  Future<void> start({required int targetClass});

  /// One camera frame, prepared as the model takes it (LS-3), at [at] into
  /// the session. A detector still busy with the last frame drops this one:
  /// frames are never queued.
  void addFrame(List<double> frame, Duration at);

  /// The CNN's embedding of a single prepared frame, for the scene change
  /// between Before and After; null when the detector has none.
  Future<List<double>?> embed(List<double> frame);

  Future<void> stop();
}
