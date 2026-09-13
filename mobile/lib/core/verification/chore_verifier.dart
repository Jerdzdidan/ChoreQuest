import '../models/chore.dart';

/// What the photo checker made of one picture.
class Verdict {
  const Verdict({this.label, this.confidence, this.modelVersion, this.inferenceMs});

  /// No checker ran. The server sends every such submission to a parent.
  static const none = Verdict();

  /// 'done' or 'not_done'.
  final String? label;

  /// Confidence in [label], from 0 to 1.
  final double? confidence;

  /// Stored with every submission, so Chapter 4 can separate real model
  /// results from anything recorded while this stand-in was in use.
  final String? modelVersion;

  /// Capture-to-result time on the handset. Left null by the stand-in, which
  /// does no real work, so it cannot pollute the performance figures.
  final int? inferenceMs;
}

/// The on-device photo checker. Slice 5.3 replaces the stand-in below with the
/// TensorFlow Lite model behind this same interface.
abstract interface class ChoreVerifier {
  Future<Verdict> verify({required String photoPath, required ChoreTemplate chore});
}

enum StubOutcome { likelyDone, unsure, likelyNotDone }

/// A stand-in until the trained model exists.
///
/// In release builds it returns no verdict at all, so every photo reaches a
/// parent rather than being judged by something that is not a model. In debug
/// builds a tester chooses what it reports, which is how all three routes can
/// be exercised before a single training photo has been taken.
class StubVerifier implements ChoreVerifier {
  StubVerifier({required this.enabled, this.outcome = StubOutcome.unsure});

  static const version = 'stub-1';

  final bool enabled;
  StubOutcome outcome;

  @override
  Future<Verdict> verify({
    required String photoPath,
    required ChoreTemplate chore,
  }) async {
    if (!enabled || !chore.modelVerifiable) return Verdict.none;

    return switch (outcome) {
      StubOutcome.likelyDone =>
        const Verdict(label: 'done', confidence: 0.95, modelVersion: version),
      StubOutcome.unsure =>
        const Verdict(label: 'done', confidence: 0.6, modelVersion: version),
      StubOutcome.likelyNotDone =>
        const Verdict(label: 'not_done', confidence: 0.95, modelVersion: version),
    };
  }
}
