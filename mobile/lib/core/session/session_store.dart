import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session.dart';

/// Keeps the session on the device between launches.
///
/// It lives in the platform's secure storage rather than plain preferences. A
/// token in shared preferences can be copied off the phone by anyone with a
/// USB cable, and this token governs a child's screen-time rules. Secure
/// storage encrypts it under a key held by the Android keystore.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Kept in memory so every API request does not go to the keystore.
  String? _token;

  static const _sessionKey = 'chorequest.session';

  /// Survives a child signing out, so the device returns to that household's
  /// avatar picker instead of asking for the code again. A family phone is
  /// paired once.
  static const _householdKey = 'chorequest.household_code';

  Future<Session> readSession() async {
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null) {
        _token = null;
        return const SignedOut();
      }
      final session =
          Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _token = session.token;
      return session;
    } catch (_) {
      // Unreadable: data from an older build, a corrupted value, or a keystore
      // key that no longer exists because the app was restored from a backup.
      // Signing out is the only safe reading of a session that cannot be
      // trusted, and it means the app root never lands in an error state.
      _token = null;
      try {
        await _storage.delete(key: _sessionKey);
      } catch (_) {
        // Nothing further to do here; the next sign-in overwrites it.
      }
      return const SignedOut();
    }
  }

  Future<String?> readToken() async => _token ?? (await readSession()).token;

  Future<void> writeSession(Session session) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));
    _token = session.token;
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _sessionKey);
    _token = null;
  }

  Future<String?> readHouseholdCode() async {
    try {
      return await _storage.read(key: _householdKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeHouseholdCode(String code) =>
      _storage.write(key: _householdKey, value: code);

  Future<void> forgetHousehold() => _storage.delete(key: _householdKey);
}
