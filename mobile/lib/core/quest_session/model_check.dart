import 'dart:math' as math;
import 'dart:typed_data';

import 'lstm_detector.dart';

/// One clip as Python prepared it and what Python made of it
/// (ml/08_convert.py --reference): the frames, and per signal every chore's
/// smoothed probability and the activity.
class ReferenceClip {
  const ReferenceClip({required this.frames, required this.expected, required this.tolerance});

  /// The frames as bytes (size x size x 3 each, 0..255), and Python's signals.
  factory ReferenceClip.fromFiles(Uint8List frameBytes, Map<String, dynamic> json) {
    final size = json['size'] as int;
    final count = json['frames'] as int;
    final each = size * size * 3;
    if (frameBytes.length != count * each) throw const FormatException('reference_frames.bin is the wrong size');
    return ReferenceClip(
      frames: [
        for (var i = 0; i < count; i++)
          Float32List.fromList([for (final b in frameBytes.sublist(i * each, (i + 1) * each)) b / 127.5 - 1]),
      ],
      expected: [
        for (final s in (json['signals'] as List).cast<Map<String, dynamic>>())
          (
            at: (s['at'] as num).toDouble(),
            chore: [for (final p in s['chore'] as List) (p as num).toDouble()],
            activity: (s['activity'] as num).toDouble(),
          ),
      ],
      tolerance: (json['tolerance'] as num?)?.toDouble() ?? 0.02,
    );
  }

  final List<Float32List> frames;
  final List<({double at, List<double> chore, double activity})> expected;
  final double tolerance;
}

/// What a benchmark run measured (M11).
class BenchmarkResult {
  const BenchmarkResult({
    required this.backboneMs,
    required this.temporalMs,
    this.signals = 0,
    this.largestDifference,
    this.tolerance,
  });

  final List<int> backboneMs;
  final List<int> temporalMs;

  /// Signals compared with Python's, and the largest difference in any
  /// probability or the activity; null without a reference clip.
  final int signals;
  final double? largestDifference;
  final double? tolerance;

  bool? get matchesPython => largestDifference == null ? null : largestDifference! <= tolerance!;

  static int mean(List<int> ms) => ms.isEmpty ? 0 : (ms.reduce((a, b) => a + b) / ms.length).round();

  static int p90(List<int> ms) {
    if (ms.isEmpty) return 0;
    final sorted = [...ms]..sort();
    return sorted[math.min(sorted.length - 1, (sorted.length * 0.9).floor())];
  }
}

/// Runs frames through the model exactly as a session does (TemporalCore),
/// timing the CNN per frame and the LSTM per window. With a reference clip,
/// its frames are used and every signal is compared with Python's; without,
/// [syntheticFrames] random frames, for timing only.
Future<BenchmarkResult> runBenchmark(
  ModelCard card,
  ModelRunner backbone,
  ModelRunner temporal, {
  ReferenceClip? reference,
  int syntheticFrames = 64,
  math.Random? random,
}) async {
  final core = TemporalCore(card);
  final rng = random ?? math.Random(7);
  final frames = reference?.frames ??
      [
        for (var i = 0; i < syntheticFrames; i++)
          Float32List.fromList(List.generate(card.inputSize * card.inputSize * 3, (_) => rng.nextDouble() * 2 - 1)),
      ];
  final backboneMs = <int>[], temporalMs = <int>[];
  final clock = Stopwatch();
  var signal = 0;
  double? largest;
  for (var i = 0; i < frames.length; i++) {
    clock
      ..reset()
      ..start();
    final embedding = await backbone.run(frames[i]);
    backboneMs.add(clock.elapsedMilliseconds);
    if (!core.add(embedding, lumaGrid(frames[i], card.inputSize, grid: card.grid))) continue;
    clock
      ..reset()
      ..start();
    final output = await temporal.run(core.window());
    temporalMs.add(clock.elapsedMilliseconds);
    core.decide(output, Duration(milliseconds: (i * 1000 / card.framesPerSecond).round()), 0);
    if (reference != null && signal < reference.expected.length) {
      final want = reference.expected[signal];
      var worst = (core.lastActivity - want.activity).abs();
      for (var c = 0; c < want.chore.length && c < core.lastChores.length; c++) {
        worst = math.max(worst, (core.lastChores[c] - want.chore[c]).abs());
      }
      largest = math.max(largest ?? 0, worst);
    }
    signal++;
  }
  return BenchmarkResult(
    backboneMs: backboneMs,
    temporalMs: temporalMs,
    signals: reference == null ? 0 : math.min(signal, reference.expected.length),
    largestDifference: largest,
    tolerance: reference?.tolerance,
  );
}
