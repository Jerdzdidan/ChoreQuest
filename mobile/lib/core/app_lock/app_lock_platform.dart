import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/phone_readiness.dart';
import 'app_lock_models.dart';

export 'app_lock_models.dart';

/// App Lock's Android side (AL-3): the watcher in AppLockService, reached
/// through AppLockChannel. Replaceable, since tests have no Android.
abstract class AppLockPlatform {
  /// This phone's key for its rules and reports.
  Future<String?> deviceKey();

  /// Null where the phone cannot say (not Android, or a test without one).
  Future<AppLockStatus?> status();

  /// Opens what turns [check] on.
  Future<FixOutcome> fix(AppLockCheck check);

  Future<void> turnOn({required int householdId, required String ticket, required String baseUrl});

  Future<void> turnOff();

  /// Starts the watcher again if Android stopped it. Whether App Lock is on.
  Future<bool> ensureRunning();

  /// What the watcher locks: the server's rules for this phone.
  Future<void> setRules(Map<String, AppSetting> rules);

  Future<List<InstalledApp>> installedApps();

  Future<Uint8List?> appIcon(String package, {int size = 96});

  Future<String?> appLabel(String package);

  /// The lock screen ChoreQuest was opened for, if it was.
  Future<LockRequest?> pendingLock();

  Future<void> clearLock();

  /// After the first minute is bought: the watcher buys the rest, with
  /// [token], and counts down.
  Future<void> startChildSession({required String package, required String token, required int balanceAfter});

  /// After a grown-up's unlock is recorded.
  Future<void> allowGrownUp(String package);

  Future<bool> openApp(String package);

  Future<void> goHome();

  /// Each time the watcher asks for the lock screen while ChoreQuest runs.
  Stream<void> get lockRequests;
}

final appLockPlatformProvider = Provider<AppLockPlatform>((ref) => MethodChannelAppLock());

/// Answered by AppLockChannel and, for notifications and battery saving,
/// by the readiness checklist's own channel (DV-1), which already opens
/// those screens.
class MethodChannelAppLock implements AppLockPlatform {
  MethodChannelAppLock() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'lock') _locks.add(null);
    });
  }

  static const _channel = MethodChannel('com.chorequest/app_lock');
  static const _readiness = MethodChannel('com.chorequest/readiness');

  final _locks = StreamController<void>.broadcast();

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> deviceKey() => _call<String>('deviceKey');

  @override
  Future<AppLockStatus?> status() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('status');
      if (raw == null) return null;
      final checks = (raw['checks'] as Map?) ?? const {};
      return AppLockStatus(
        enabled: raw['enabled'] == true,
        running: raw['running'] == true,
        checks: {for (final check in AppLockCheck.values) check: checks[check.key] == true},
        phoneName: raw['phone_name'] as String? ?? 'This phone',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<FixOutcome> fix(AppLockCheck check) async {
    try {
      final raw = switch (check) {
        AppLockCheck.usageAccess || AppLockCheck.overlay =>
          await _channel.invokeMethod<String>('open', {'what': check.key}),
        AppLockCheck.notifications || AppLockCheck.battery =>
          await _readiness.invokeMethod<String>('fix', {'row': check.key}),
      };
      return FixOutcome.parse(raw);
    } catch (_) {
      return FixOutcome.unavailable;
    }
  }

  @override
  Future<void> turnOn({required int householdId, required String ticket, required String baseUrl}) =>
      _call<void>('turnOn', {'household_id': householdId, 'ticket': ticket, 'base_url': baseUrl});

  @override
  Future<void> turnOff() => _call<void>('turnOff');

  @override
  Future<bool> ensureRunning() async => await _call<bool>('ensureRunning') ?? false;

  @override
  Future<void> setRules(Map<String, AppSetting> rules) => _call<void>('setRules', {
        'rules': {
          for (final entry in rules.entries)
            if (entry.value != AppSetting.open) entry.key: entry.value.key,
        },
      });

  @override
  Future<List<InstalledApp>> installedApps() async {
    final raw = await _call<List<Object?>>('installedApps') ?? const [];
    return [
      for (final app in raw.whereType<Map<Object?, Object?>>())
        InstalledApp(package: '${app['package']}', label: '${app['label']}'),
    ];
  }

  @override
  Future<Uint8List?> appIcon(String package, {int size = 96}) =>
      _call<Uint8List>('appIcon', {'package': package, 'size': size});

  @override
  Future<String?> appLabel(String package) => _call<String>('appLabel', {'package': package});

  @override
  Future<LockRequest?> pendingLock() async {
    final raw = await _call<Map<Object?, Object?>>('pendingLock');
    if (raw == null) return null;
    final package = raw['package'] as String?;
    if (package == null) return null;
    return LockRequest(
      package: package,
      label: raw['label'] as String? ?? package,
      reason: LockReason.parse(raw['reason'] as String?),
      setting: AppSetting.parse(raw['setting'] as String?),
    );
  }

  @override
  Future<void> clearLock() => _call<void>('clearLock');

  @override
  Future<void> startChildSession({required String package, required String token, required int balanceAfter}) =>
      _call<void>('startChildSession', {'package': package, 'token': token, 'balance_after': balanceAfter});

  @override
  Future<void> allowGrownUp(String package) => _call<void>('allowGrownUp', {'package': package});

  @override
  Future<bool> openApp(String package) async => await _call<bool>('openApp', {'package': package}) ?? false;

  @override
  Future<void> goHome() => _call<void>('goHome');

  @override
  Stream<void> get lockRequests => _locks.stream;
}
