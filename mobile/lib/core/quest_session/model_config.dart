import 'dart:convert';
import 'dart:io';

import '../api/api_client.dart';
import 'done_gate.dart';

/// The movement model's thresholds as the server serves them (BE-6): the
/// Done gate's numbers per chore with defaults, the evidence bands, and the
/// longest an alarm may ring. Tuned by the calibration script, never by the
/// app, and never per child.
class ModelConfig {
  const ModelConfig(this._json);

  factory ModelConfig.fromJson(Map<String, dynamic> json) => ModelConfig(json);

  /// What the phone uses before it has ever reached the server: the same
  /// starting values the server's file begins with.
  static const fallback = ModelConfig({
    'version': 'built-in',
    'defaults': {'min_probability': 0.6, 'min_activity': 0.3, 'min_seconds': 30, 'gap_seconds': 8},
    'chores': <String, Object?>{},
    'max_ring_minutes': 10,
  });

  final Map<String, dynamic> _json;

  Map<String, dynamic> get json => _json;

  String get version => _json['version'] as String? ?? 'unknown';

  int get maxRingMinutes => (_json['max_ring_minutes'] as num?)?.toInt() ?? 10;

  Map<String, dynamic> get _defaults => switch (_json['defaults']) {
        final Map<dynamic, dynamic> defaults => defaults.cast<String, dynamic>(),
        _ => const {},
      };

  /// The Done gate's numbers for one chore: the chore's own entry in the
  /// config, then the chore's minimum time from the catalogue, then the
  /// defaults.
  GateThresholds thresholdsFor(String? choreKey, {int? catalogueMinSeconds}) {
    // An empty map can arrive as an empty JSON list from PHP; either way,
    // anything that is not a chore's entry is no entry.
    final chores = _json['chores'];
    final entry = choreKey != null && chores is Map ? chores[choreKey] : null;
    final chore = entry is Map ? entry.cast<String, dynamic>() : const <String, dynamic>{};
    num? pick(String key) => (chore[key] as num?) ?? (_defaults[key] as num?);
    return GateThresholds(
      minProbability: (pick('min_probability') ?? 0.6).toDouble(),
      minActivity: (pick('min_activity') ?? 0.3).toDouble(),
      minSeconds: ((chore['min_seconds'] as num?) ?? catalogueMinSeconds ?? (_defaults['min_seconds'] as num?) ?? 30).toInt(),
      gapSeconds: (pick('gap_seconds') ?? 8).toInt(),
    );
  }
}

/// Fetches the model config at every app open and keeps the last copy on the
/// phone, so a session offline still has thresholds. A copy whose version
/// has not changed is left as it is.
class ModelConfigStore {
  ModelConfigStore({required this.api, required this.file});

  final ApiClient api;

  /// Where the last copy lives, in the app's own documents folder.
  final File file;

  /// The freshest config there is: the server's, else the saved copy, else
  /// the built-in starting values.
  Future<ModelConfig> load() async {
    try {
      final fetched = ModelConfig.fromJson(await api.get('/model-config'));
      final saved = await _saved();
      if (saved?.version != fetched.version) {
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(fetched.json), flush: true);
      }
      return fetched;
    } catch (_) {
      return await _saved() ?? ModelConfig.fallback;
    }
  }

  Future<ModelConfig?> _saved() async {
    try {
      if (!await file.exists()) return null;
      return ModelConfig.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
