import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/app_lock/app_lock_platform.dart';
import '../../core/session/session_controller.dart';

/// An [ApiClient] that sends [token] rather than the session's. The lock
/// screen signs a child or a grown-up in for one unlock only, so whoever is
/// signed in on the phone stays signed in. Null sends no token.
typedef ClientForToken = ApiClient Function(String? token);

final clientForTokenProvider = Provider<ClientForToken>(
  (ref) => (token) => ApiClient(readToken: () async => token),
);

final appLockApiProvider = Provider<AppLockApi>(
  (ref) => AppLockApi(ref.watch(apiClientProvider), ref.watch(clientForTokenProvider)),
);

/// A grown-up signed in for one unlock: their token, and what the server
/// says about them.
typedef GrownUpPass = ({String token, int parentId, String? email, String? pinTicket});

/// App Lock's calls to the server (AL-2, AL-4).
class AppLockApi {
  AppLockApi(this._session, this._clientFor);

  /// As whoever is signed in on the phone.
  final ApiClient _session;
  final ClientForToken _clientFor;

  /// This phone's rules: package to setting. An app with none is Open.
  Future<Map<String, AppSetting>> rules(String deviceKey) async =>
      _parseRules(await _session.get('/app-rules', query: {'device_key': deviceKey}));

  /// Parent only. Answers with all of the phone's rules afterwards.
  Future<Map<String, AppSetting>> setRules(String deviceKey, Map<String, AppSetting> changes) async =>
      _parseRules(await _session.patch('/app-rules', body: {
        'device_key': deviceKey,
        'rules': [
          for (final entry in changes.entries) {'package': entry.key, 'setting': entry.value.key},
        ],
      }));

  /// Parent only: App Lock on, on this phone. The ticket its watcher reports with.
  Future<String> turnOnPhone({required String deviceKey, required String name}) async {
    final body = await _session.put('/app-lock/phones', body: {'device_key': deviceKey, 'name': name});
    return body['phone_ticket'] as String;
  }

  Future<void> turnOffPhone(String deviceKey) =>
      _session.delete('/app-lock/phones?device_key=${Uri.encodeQueryComponent(deviceKey)}');

  // The lock screen (AL-6).

  Future<String> childToken({required String householdCode, required int childId, required String pin}) async {
    final body = await _clientFor(null).post(
      '/child/login',
      body: {'household_code': householdCode, 'child_id': childId, 'pin': pin},
    );
    return body['token'] as String;
  }

  /// The minute that opens the app, which also records the child's unlock.
  /// Their balance after it. A 409 [ApiRejected] means no time is left.
  Future<int> openWithMinute({required String token, required String deviceKey, required String package}) async {
    final body = await _clientFor(token).post(
      '/screen-time/minutes',
      body: {'device_key': deviceKey, 'package': package, 'opening': true},
    );
    return body['balance_minutes'] as int? ?? 0;
  }

  /// A grown-up's PIN, through the ordinary PIN sign-in with its five tries.
  Future<GrownUpPass> grownUpWithPin({
    required String householdCode,
    required int parentId,
    required String pin,
    required String pinTicket,
  }) async =>
      _pass(await _clientFor(null).post(
        '/parent/pin-login',
        body: {'household_code': householdCode, 'parent_id': parentId, 'pin': pin, 'pin_ticket': pinTicket},
      ));

  /// A grown-up's password, when their PIN is off or this phone has not seen
  /// their password before.
  Future<GrownUpPass> grownUpWithPassword({required String email, required String password}) async =>
      _pass(await _clientFor(null).post('/login', body: {'email': email, 'password': password}));

  /// Rule 10: recorded before the app opens.
  Future<void> recordGrownUpUnlock({required String token, required String deviceKey, required String package}) =>
      _clientFor(token).post('/app-unlocks', body: {'device_key': deviceKey, 'package': package});

  /// Best effort: an unlock's token is thrown away when it is done.
  Future<void> signOut(String token) async {
    try {
      await _clientFor(token).post('/logout');
    } on ApiException {
      // Offline, or already gone.
    }
  }

  static GrownUpPass _pass(Map<String, dynamic> body) {
    final parent = body['parent'] as Map<String, dynamic>? ?? const {};
    return (
      token: body['token'] as String,
      parentId: parent['id'] as int? ?? 0,
      email: parent['email'] as String?,
      pinTicket: body['pin_ticket'] as String?,
    );
  }

  static Map<String, AppSetting> _parseRules(Map<String, dynamic> body) => {
        for (final rule in (body['rules'] as List? ?? const []).cast<Map<String, dynamic>>())
          rule['package'] as String: AppSetting.parse(rule['setting'] as String?),
      };
}
