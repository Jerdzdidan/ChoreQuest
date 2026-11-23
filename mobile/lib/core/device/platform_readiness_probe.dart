import 'package:flutter/services.dart';

import 'phone_readiness.dart';

/// Answered by MainActivity from Android's own settings.
const _channel = MethodChannel('com.chorequest/readiness');

/// The checklist's rows as Android reports them (DV-1).
class PlatformReadinessProbe implements ReadinessProbe {
  const PlatformReadinessProbe({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  @override
  Future<ReadinessResult?> check() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('check');
      if (raw == null) return null;
      return ReadinessResult(
        rows: {for (final row in ReadinessRow.values) row: raw[row.key] == true},
        checkedAt: _now(),
        makerBattery: raw['maker_battery'] == true,
      );
    } catch (_) {
      // No handler (a test, or a platform without one): nothing to say.
      return null;
    }
  }

  @override
  Future<FixOutcome> fix(ReadinessRow row) => _ask('fix', {'row': row.key});

  @override
  Future<FixOutcome> openMakerBattery() => _ask('openMakerBattery');

  Future<FixOutcome> _ask(String method, [Map<String, Object?>? arguments]) async {
    try {
      return FixOutcome.parse(await _channel.invokeMethod<String>(method, arguments));
    } catch (_) {
      return FixOutcome.unavailable;
    }
  }
}
