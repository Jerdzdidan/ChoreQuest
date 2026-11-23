import 'chore_detector.dart';

/// What a phone without the movement model has (LS-5): nothing to watch
/// with. A session that gets this runs manual, Before and After for the
/// grown-up, and says so in its evidence, so the child is never left unable
/// to finish.
class NoModelDetector implements ChoreDetector {
  const NoModelDetector();

  @override
  bool get available => false;

  @override
  String get version => 'none';

  @override
  int? get meanModelMs => null;

  @override
  bool get needsFrames => false;

  @override
  Stream<DetectorSignal> get signals => const Stream.empty();

  @override
  Future<void> start({required int targetClass}) async {}

  @override
  void addFrame(List<double> frame, Duration at) {}

  @override
  Future<List<double>?> embed(List<double> frame) async => null;

  @override
  Future<void> stop() async {}
}
