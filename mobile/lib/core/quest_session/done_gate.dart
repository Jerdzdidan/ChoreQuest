import 'chore_detector.dart';

/// The numbers the Done gate works to for one chore, from the model config
/// (BE-6), which the calibration script tunes without a new app.
class GateThresholds {
  const GateThresholds({
    required this.minProbability,
    required this.minSeconds,
    required this.gapSeconds,
    this.minActivity = 0.3,
  });

  /// A moment counts only when the model gives the assigned chore at least
  /// this probability...
  final double minProbability;

  /// ...and sees at least this much task-like movement. Energetic movement
  /// that does not look like the chore never counts, nor does standing still
  /// beside it.
  final double minActivity;

  /// Seconds of matching movement before Done appears.
  final int minSeconds;

  /// A pause up to this long between matching moments (a child fetching the
  /// dustpan) counts as part of the work; a longer one does not count, but
  /// nothing already earned is ever taken away.
  final int gapSeconds;
}

/// What the gate tells the session.
sealed class GateEvent {
  const GateEvent();
}

/// The first movement that matches the chore: this stops the alarm (DV-6).
class FirstMovement extends GateEvent {
  const FirstMovement(this.at);

  final Duration at;
}

/// How far along the child is, 0 to 1.
class Progress extends GateEvent {
  const Progress(this.fraction, this.activeSeconds);

  final double fraction;
  final double activeSeconds;
}

/// Enough matching movement: Done may appear, and stays.
class DoneAvailable extends GateEvent {
  const DoneAvailable(this.at);

  final Duration at;
}

/// Works out, from the detector's signals, when the child first moves like
/// the chore, how far along they are, and when Done becomes available (LS-6).
///
/// Pure: no clock and no Flutter; each signal carries its own time, so a
/// test can feed it made-up signals and read the answer.
class DoneGate {
  DoneGate(this.thresholds);

  final GateThresholds thresholds;

  Duration? _firstMovement;
  Duration? _lastMatch;
  Duration? _doneAt;
  var _activeSeconds = 0.0;

  // What the evidence summary reports (LS-8).
  var _signals = 0;
  var _probabilitySum = 0.0;
  var _probabilityMax = 0.0;
  Duration _lastAt = Duration.zero;
  final _timeline = <(int, double)>[];

  bool get movementSeen => _firstMovement != null;
  bool get doneAvailable => _doneAt != null;
  Duration? get firstMovementAt => _firstMovement;

  /// Seconds of movement that matched the chore so far.
  double get activeSeconds => _activeSeconds;

  /// 0 to 1, reaching 1 when Done is available.
  double get progress => doneAvailable ? 1 : (_activeSeconds / thresholds.minSeconds).clamp(0.0, 1.0);

  double? get meanProbability => _signals == 0 ? null : _probabilitySum / _signals;
  double? get maxProbability => _signals == 0 ? null : _probabilityMax;

  /// The session so far, by the detector's own clock.
  Duration get lastSignalAt => _lastAt;

  /// One point every 5 seconds: (second, probability of the chore).
  List<(int, double)> get timeline => List.unmodifiable(_timeline);

  /// Whether this moment looks like the assigned chore being done.
  bool matches(DetectorSignal signal) =>
      signal.targetProbability >= thresholds.minProbability && signal.activity >= thresholds.minActivity;

  /// Takes one signal and returns what it changed, in order.
  List<GateEvent> feed(DetectorSignal signal) {
    _record(signal);
    if (!matches(signal)) return const [];

    final events = <GateEvent>[];
    if (_firstMovement == null) {
      _firstMovement = signal.at;
      events.add(FirstMovement(signal.at));
    }

    final last = _lastMatch;
    if (last != null) {
      final gap = signal.at - last;
      if (!gap.isNegative && gap.inMilliseconds <= thresholds.gapSeconds * 1000) {
        _activeSeconds += gap.inMilliseconds / 1000;
      }
    }
    _lastMatch = signal.at;

    if (!doneAvailable) {
      events.add(Progress(progress, _activeSeconds));
      if (_activeSeconds >= thresholds.minSeconds) {
        _doneAt = signal.at;
        events.add(DoneAvailable(signal.at));
      }
    }
    return events;
  }

  void _record(DetectorSignal signal) {
    _signals++;
    _probabilitySum += signal.targetProbability;
    if (signal.targetProbability > _probabilityMax) _probabilityMax = signal.targetProbability;
    if (signal.at > _lastAt) _lastAt = signal.at;
    final second = signal.at.inSeconds - signal.at.inSeconds % 5;
    if (_timeline.isEmpty || _timeline.last.$1 < second) {
      _timeline.add((second, double.parse(signal.targetProbability.toStringAsFixed(2))));
    }
  }
}
