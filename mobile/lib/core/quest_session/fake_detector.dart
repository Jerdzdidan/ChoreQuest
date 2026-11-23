import 'dart:async';

import 'chore_detector.dart';

/// What the fake detector pretends the child is doing.
enum FakeBehaviour {
  /// Standing still: no movement, nothing like the chore.
  idle,

  /// Doing the assigned chore.
  doingTheChore,

  /// Moving a lot, but not like the chore.
  somethingElse,
}

/// A stand-in for the movement model, for debug builds (LS-4), the same
/// trick as the old StubVerifier: the whole session (ring, Start, the alarm
/// stopping, Done appearing, Before and After, the upload) runs end to end
/// before any model exists.
///
/// It reports idle for [startAfter], then the chore, once every [interval].
/// The debug panel on the session screen can switch what it pretends at any
/// time.
class FakeDetector implements ChoreDetector {
  FakeDetector({
    this.startAfter = const Duration(seconds: 3),
    this.interval = const Duration(seconds: 1),
    this.unavailable = false,
  });

  final Duration startAfter;
  final Duration interval;

  /// Pretend no model could be loaded, to try the manual fallback.
  final bool unavailable;

  final _signals = StreamController<DetectorSignal>.broadcast();
  final _clock = Stopwatch();
  Timer? _timer;
  FakeBehaviour? _pinned;

  /// What it pretends now: as pinned from the debug panel, otherwise idle
  /// until [startAfter] and the chore after.
  FakeBehaviour get behaviour =>
      _pinned ?? (_clock.elapsed < startAfter ? FakeBehaviour.idle : FakeBehaviour.doingTheChore);

  set behaviour(FakeBehaviour value) => _pinned = value;

  @override
  bool get available => !unavailable;

  @override
  String get version => 'fake-1';

  @override
  Stream<DetectorSignal> get signals => _signals.stream;

  @override
  Future<void> start({required int targetClass}) async {
    _clock
      ..reset()
      ..start();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      if (_signals.isClosed) return;
      _signals.add(signalFor(behaviour, _clock.elapsed, targetClass));
    });
  }

  /// The signal a moment of [behaviour] gives: pure, so a test can build the
  /// same signals without a timer.
  static DetectorSignal signalFor(FakeBehaviour behaviour, Duration at, int targetClass) => switch (behaviour) {
        FakeBehaviour.idle => DetectorSignal(at: at, targetProbability: 0.05, activity: 0.03, topClass: null),
        FakeBehaviour.doingTheChore => DetectorSignal(at: at, targetProbability: 0.9, activity: 0.8, topClass: targetClass),
        FakeBehaviour.somethingElse => DetectorSignal(at: at, targetProbability: 0.08, activity: 0.9, topClass: null),
      };

  @override
  void addFrame(List<double> frame, Duration at) {}

  @override
  Future<List<double>?> embed(List<double> frame) async => null;

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _clock.stop();
    await _signals.close();
  }
}
