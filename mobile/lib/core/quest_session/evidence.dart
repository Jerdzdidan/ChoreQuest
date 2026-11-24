import 'dart:convert';
import 'dart:math' as math;

import 'quest_session.dart';

/// The most an evidence summary may weigh (LS-8); the server takes up to
/// twice this.
const evidenceMaxBytes = 4096;

/// The most timeline points kept. One every 5 seconds covers 10 minutes;
/// a longer session keeps every second, third... point instead.
const _maxTimeline = 120;

/// The cosine distance between the Before and After embeddings: 0 when the
/// scene is the same, rising as it changes. Null when either is missing or
/// they cannot be compared.
double? sceneChange(List<double>? before, List<double>? after) {
  if (before == null || after == null || before.length != after.length || before.isEmpty) return null;
  var dot = 0.0, a = 0.0, b = 0.0;
  for (var i = 0; i < before.length; i++) {
    dot += before[i] * after[i];
    a += before[i] * before[i];
    b += after[i] * after[i];
  }
  if (a == 0 || b == 0) return null;
  return double.parse((1 - dot / (math.sqrt(a) * math.sqrt(b))).clamp(0.0, 2.0).toStringAsFixed(3));
}

/// The small summary a finished session sends with its two photos (LS-8),
/// with no picture in it: how long the session ran, how much of it matched
/// the chore and how closely, a coarse timeline, how much the scene changed,
/// the camera, the model's speed and the phone, and when it started and
/// finished. A manual session sends the same with no model figures.
///
/// The server keeps only these keys (App\Domain\Verification\Evidence).
Map<String, Object?> buildEvidence({
  required QuestSession session,
  required String? choreKey,
  required String? modelVersion,
  required String camera,
  double? sceneChangeScore,
  bool? sceneFits,
  int? meanModelMs,
  String? phoneModel,
}) {
  final motion = session.mode == CheckMode.motion;
  final gate = session.gate;
  final seconds = session.sessionSeconds;
  final active = gate.activeSeconds.round();

  var timeline = gate.timeline;
  if (timeline.length > _maxTimeline) {
    final step = (timeline.length / _maxTimeline).ceil();
    timeline = [for (var i = 0; i < timeline.length; i += step) timeline[i]];
  }

  final evidence = <String, Object?>{
    'mode': motion ? 'lstm' : 'manual',
    'chore_key': choreKey,
    'session_seconds': seconds,
    if (motion) ...{
      'model_version': modelVersion,
      'active_seconds': active,
      'mean_probability': _rounded(gate.meanProbability),
      'max_probability': _rounded(gate.maxProbability),
      'matched_share': seconds == 0 ? 0.0 : _rounded(math.min(1.0, active / seconds)),
      'timeline': [for (final (second, p) in timeline) [second, p]],
      'mean_model_ms': meanModelMs,
    },
    'scene_change': sceneChangeScore,
    'scene_fits': sceneFits,
    'camera': camera,
    'model_unavailable': session.modelUnavailable,
    'no_strap': session.manualReason == ManualReason.noStrap,
    'no_back_camera': session.manualReason == ManualReason.noBackCamera,
    'phone_model': phoneModel,
    'started_at': session.startedAt?.toUtc().toIso8601String(),
    'finished_at': session.finishedAt?.toUtc().toIso8601String(),
  }..removeWhere((_, value) => value == null);

  // Never over the limit: the timeline is the only part that grows, so it is
  // thinned until the whole fits.
  while (utf8.encode(jsonEncode(evidence)).length > evidenceMaxBytes) {
    final points = (evidence['timeline'] as List?) ?? const [];
    if (points.length < 2) break;
    evidence['timeline'] = [for (var i = 0; i < points.length; i += 2) points[i]];
  }
  return evidence;
}

double? _rounded(double? value) => value == null ? null : double.parse(value.toStringAsFixed(3));
