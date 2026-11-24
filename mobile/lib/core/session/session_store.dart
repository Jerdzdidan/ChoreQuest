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

  /// The grown-ups who signed in on this phone with their password, by id:
  /// their email, to fill in next time, and the pin ticket that lets their
  /// PIN work here (rule 6). Survives signing out, like the household.
  static const _grownUpsKey = 'chorequest.grown_ups';

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

  Future<Map<int, KnownGrownUp>> readGrownUps() async {
    try {
      final raw = await _storage.read(key: _grownUpsKey);
      if (raw == null) return const {};
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in json.entries)
          int.parse(entry.key): KnownGrownUp.fromJson(entry.value as Map<String, dynamic>),
      };
    } catch (_) {
      // Unreadable: the grown-ups sign in with their password again.
      return const {};
    }
  }

  /// Remembers a grown-up after a sign-in. A null [pinTicket] keeps the one
  /// already kept.
  ///
  /// Best effort: if the keystore cannot be written, the sign-in or the
  /// change that led here still stands, and the grown-up only types their
  /// password once more before their PIN works on this phone.
  Future<void> rememberGrownUp(int id, {required String email, String? pinTicket}) async {
    try {
      final known = {...await readGrownUps()};
      known[id] = KnownGrownUp(email: email, pinTicket: pinTicket ?? known[id]?.pinTicket);
      await _storage.write(
        key: _grownUpsKey,
        value: jsonEncode({for (final entry in known.entries) '${entry.key}': entry.value.toJson()}),
      );
    } catch (_) {
      // Nothing further: see above.
    }
  }
}

/// A grown-up this phone has seen sign in with their password.
class KnownGrownUp {
  const KnownGrownUp({required this.email, this.pinTicket});

  factory KnownGrownUp.fromJson(Map<String, dynamic> json) =>
      KnownGrownUp(email: json['email'] as String, pinTicket: json['pin_ticket'] as String?);

  final String email;

  /// From the server at their last password sign-in here. Without it their
  /// PIN does not work on this phone.
  final String? pinTicket;

  Map<String, dynamic> toJson() => {'email': email, 'pin_ticket': pinTicket};
}
