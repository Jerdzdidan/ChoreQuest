import 'dart:async';
import 'dart:typed_data';

import 'chore_detector.dart';

/// What ml/08_convert.py writes beside the two model files: what they take,
/// what they give, and which version they are.
class ModelCard {
  const ModelCard({
    required this.version,
    required this.inputSize,
    required this.framesPerSecond,
    required this.window,
    required this.embedding,
    required this.classes,
    required this.scenes,
    required this.choreFrom,
    required this.choreTo,
    required this.activityAt,
    required this.grid,
  });

  /// Throws when the card does not describe a model this app can run.
  factory ModelCard.fromJson(Map<String, dynamic> json) {
    final outputs = json['outputs'] as Map<String, dynamic>;
    final chore = (outputs['chore'] as List).cast<int>();
    final card = ModelCard(
      version: json['version'] as String,
      inputSize: json['input_size'] as int,
      framesPerSecond: json['frames_per_second'] as int,
      window: json['window'] as int,
      embedding: json['embedding'] as int,
      classes: (json['classes'] as List).cast<String>(),
      scenes: (json['scenes'] as List).cast<String>(),
      choreFrom: chore[0],
      choreTo: chore[1],
      activityAt: outputs['activity'] as int,
      grid: json['movement_energy_grid'] as int? ?? 16,
    );
    if (card.choreTo - card.choreFrom != card.classes.length || card.window < 1 || card.framesPerSecond < 1) {
      throw const FormatException('model_card.json does not match its own outputs');
    }
    return card;
  }

  final String version;
  final int inputSize;
  final int framesPerSecond;
  final int window;
  final int embedding;

  /// Every chore by model class, then "other".
  final List<String> classes;
  final List<String> scenes;

  /// Where each head sits in temporal.tflite's one output vector.
  final int choreFrom;
  final int choreTo;
  final int activityAt;

  /// Movement energy is sampled on a grid x grid of points.
  final int grid;

  int get outputLength => activityAt + 1 + scenes.length;
}

/// Runs one model file: a prepared input in, its output vector out. One at a
/// time; a call made while another runs waits its turn.
abstract class ModelRunner {
  Future<Float32List> run(Float32List input);
}

/// The brightness of a prepared frame (RGB, -1..1, size x size) at a
/// grid x grid of points, for movement energy. As ml/pipeline.py samples it.
Float32List lumaGrid(List<double> frame, int size, {int grid = 16}) {
  final out = Float32List(grid * grid);
  for (var gy = 0; gy < grid; gy++) {
    final y = (gy * size) ~/ grid;
    for (var gx = 0; gx < grid; gx++) {
      final x = (gx * size) ~/ grid;
      final at = (y * size + x) * 3;
      out[gy * grid + gx] = 0.299 * frame[at] + 0.587 * frame[at + 1] + 0.114 * frame[at + 2];
    }
  }
  return out;
}

/// How much the picture changed between two frames' grids, 0 to 1: the mean
/// absolute change in brightness, halved. None for the first frame.
/// ml/pipeline.py movement_energy, line for line.
double movementEnergy(Float32List? previous, Float32List current) {
  if (previous == null) return 0;
  var sum = 0.0;
  for (var i = 0; i < current.length; i++) {
    sum += (current[i] - previous[i]).abs();
  }
  return sum / current.length / 2;
}

/// The detector's arithmetic, with no model in it: the last [ModelCard.window]
/// embeddings with their movement energy, the LSTM's input built from them,
/// and its output smoothed into a signal. Training replays exactly this
/// (ml/pipeline.py: window_at, signal_frames, smooth), so thresholds
/// calibrated there hold here.
class TemporalCore {
  TemporalCore(this.card, {this.smoothing = 3});

  final ModelCard card;

  /// Each signal is the mean of this many of the latest outputs.
  final int smoothing;

  final _embeddings = <Float32List>[];
  final _energy = <double>[];
  final _outputs = <Float32List>[];
  Float32List? _lastGrid;
  var _frames = 0;

  /// Every chore's smoothed probability and the smoothed activity at the
  /// last signal, for checking the phone against Python (M11).
  Float32List lastChores = Float32List(0);
  double lastActivity = 0;

  void reset() {
    _embeddings.clear();
    _energy.clear();
    _outputs.clear();
    _lastGrid = null;
    _frames = 0;
  }

  /// One frame's embedding and brightness grid. True when the LSTM is due:
  /// after every [ModelCard.framesPerSecond]-th frame, about once a second.
  bool add(Float32List embedding, Float32List grid) {
    _energy.add(movementEnergy(_lastGrid, grid));
    _lastGrid = grid;
    _embeddings.add(embedding);
    if (_embeddings.length > card.window) {
      _embeddings.removeAt(0);
      _energy.removeAt(0);
    }
    _frames++;
    return _frames % card.framesPerSecond == 0;
  }

  /// The LSTM's input now: the last window of embeddings, each followed by
  /// its movement energy, the earliest repeated at the front while there are
  /// fewer.
  Float32List window() {
    final width = card.embedding + 1;
    final out = Float32List(card.window * width);
    final missing = card.window - _embeddings.length;
    for (var row = 0; row < card.window; row++) {
      final from = row < missing ? 0 : row - missing;
      out.setRange(row * width, row * width + card.embedding, _embeddings[from]);
      out[row * width + card.embedding] = _energy[from];
    }
    return out;
  }

  /// The LSTM's output for the window just built, as a signal for the
  /// chore with class [target]: the mean of the last [smoothing] outputs.
  DetectorSignal decide(Float32List output, Duration at, int target) {
    _outputs.add(output);
    if (_outputs.length > smoothing) _outputs.removeAt(0);
    final chores = card.choreTo - card.choreFrom;
    final mean = Float32List(chores);
    var activity = 0.0;
    for (final o in _outputs) {
      for (var c = 0; c < chores; c++) {
        mean[c] += o[card.choreFrom + c] / _outputs.length;
      }
      activity += o[card.activityAt] / _outputs.length;
    }
    var top = 0;
    for (var c = 1; c < chores; c++) {
      if (mean[c] > mean[top]) top = c;
    }
    lastChores = mean;
    lastActivity = activity;
    return DetectorSignal(at: at, targetProbability: mean[target], activity: activity, topClass: top);
  }
}

/// The real detector (LS-5): the CNN runs on each frame the camera gives
/// (about four a second), its embedding goes into a ring buffer, and about
/// once a second the LSTM looks at the buffer. A frame that arrives while
/// the last is still running is dropped, never queued.
class LstmDetector implements ChoreDetector {
  LstmDetector({required this.card, required this.backbone, required this.temporal}) : _core = TemporalCore(card);

  final ModelCard card;
  final ModelRunner backbone;
  final ModelRunner temporal;
  final TemporalCore _core;

  final _signals = StreamController<DetectorSignal>.broadcast();
  final _sinceFrame = Stopwatch();
  int? _target;
  var _busy = false;
  var _stopped = false;
  var _timed = 0;
  var _totalMs = 0;

  @override
  bool get available => true;

  @override
  String get version => card.version;

  @override
  int? get meanModelMs => _timed == 0 ? null : (_totalMs / _timed).round();

  @override
  bool get needsFrames => true;

  @override
  Stream<DetectorSignal> get signals => _signals.stream;

  @override
  Future<void> start({required int targetClass}) async {
    _target = targetClass;
    _stopped = false;
    _core.reset();
  }

  @override
  void addFrame(List<double> frame, Duration at) {
    final target = _target;
    if (target == null || _busy || _stopped) return;
    _busy = true;
    unawaited(_process(frame is Float32List ? frame : Float32List.fromList(frame), at, target));
  }

  Future<void> _process(Float32List frame, Duration at, int target) async {
    try {
      _sinceFrame
        ..reset()
        ..start();
      final embedding = await backbone.run(frame);
      final due = _core.add(embedding, lumaGrid(frame, card.inputSize, grid: card.grid));
      if (due && !_stopped) {
        final output = await temporal.run(_core.window());
        if (!_stopped) _signals.add(_core.decide(output, at, target));
      }
      _totalMs += _sinceFrame.elapsedMilliseconds;
      _timed++;
    } catch (_) {
      // One frame the model could not take: the next one tries again.
    } finally {
      _busy = false;
    }
  }

  @override
  Future<List<double>?> embed(List<double> frame) async {
    try {
      return await backbone.run(frame is Float32List ? frame : Float32List.fromList(frame));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _target = null;
    await _signals.close();
  }
}
