import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../notifications/local_notifier.dart';
import 'session.dart';
import 'session_store.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(readToken: ref.watch(sessionStoreProvider).readToken),
);

final sessionProvider =
    AsyncNotifierProvider<SessionController, Session>(SessionController.new);

/// Owns who is signed in, and is the only thing that changes it.
///
/// The sign-in methods deliberately let [ApiException]s escape to the calling
/// screen instead of moving this notifier into an error state. A wrong PIN is
/// a message on the PIN screen, not a reason to tear down the whole app, so the
/// session only changes when a sign-in actually succeeds.
class SessionController extends AsyncNotifier<Session> {
  SessionStore get _store => ref.read(sessionStoreProvider);
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  Future<Session> build() async {
    final stored = await _store.readSession();

    // Open straight into the stored shell, even with no connection, and check
    // the token with the server afterwards. A household whose Wi-Fi drops
    // should still see the right home screen.
    if (stored is! SignedOut) {
      unawaited(_revalidate(stored));
    }
    return stored;
  }

  Future<void> signInParent({
    required String email,
    required String password,
  }) async {
    final body = await _api.post(
      '/login',
      body: {'email': email, 'password': password},
    );
    await _adopt(ParentSession.fromAuthResponse(body));
  }

  Future<void> registerParent({
    required String name,
    required String email,
    required String password,
  }) async {
    final body = await _api.post(
      '/register',
      body: {
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': password,
      },
    );
    await _adopt(ParentSession.fromAuthResponse(body));
  }

  Future<void> signInChild({
    required String householdCode,
    required int childId,
    required String pin,
  }) async {
    final body = await _api.post(
      '/child/login',
      body: {'household_code': householdCode, 'child_id': childId, 'pin': pin},
    );
    await _store.writeHouseholdCode(householdCode);
    await _adopt(
      ChildSession.fromAuthResponse(body, householdCode: householdCode),
    );
  }

  /// Revoking the token on the server is best effort. Signing out on the
  /// device always happens, connected or not.
  Future<void> signOut() async {
    try {
      await _api.post('/logout');
    } on ApiException {
      // Offline, or the token was already revoked. Neither should keep
      // someone signed in on this phone.
    }
    await _endSession();
  }

  Future<void> _adopt(Session session) async {
    await _store.writeSession(session);
    state = AsyncData(session);
  }

  /// Forgets the session on this phone and clears the notifications it
  /// raised, so a parent's review requests are not left in the shade for the
  /// child who signs in next.
  Future<void> _endSession() async {
    await _store.clearSession();
    await ref.read(appNotifierProvider).clearAll();
    state = const AsyncData(SignedOut());
  }

  Future<void> _revalidate(Session stored) async {
    try {
      final me = await _api.get('/me');
      if (!ref.mounted || !_stillSignedInAs(stored)) return;

      final refreshed = switch (stored) {
        ParentSession() when me['type'] == 'parent' =>
          stored.withProfile(me['parent'] as Map<String, dynamic>),
        ChildSession() when me['type'] == 'child' =>
          stored.withProfile(me['child'] as Map<String, dynamic>),
        _ => null,
      };

      if (refreshed == null) {
        // The token belongs to a different kind of account than was stored.
        // Nothing sensible can be shown; start again.
        await _endSession();
        return;
      }

      await _adopt(refreshed);
    } on ApiUnauthorised {
      // Revoked server-side, for instance a parent removed this child's
      // profile. Only a definite "not authorised" signs the device out.
      if (!ref.mounted || !_stillSignedInAs(stored)) return;
      await _endSession();
    } on ApiException {
      // Unreachable, or a server fault. Keep the stored session.
    }
  }

  /// Guards against a sign-out landing while revalidation was in flight: the
  /// late response must not resurrect a session the person just ended.
  bool _stillSignedInAs(Session stored) {
    final current = state;
    return current is AsyncData<Session> && current.value.token == stored.token;
  }
}
