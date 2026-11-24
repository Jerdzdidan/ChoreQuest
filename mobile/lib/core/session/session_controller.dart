import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../notifications/local_notifier.dart';
import 'device_timezone.dart';
import 'session.dart';
import 'session_store.dart';
import 'timezone_reporter.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(readToken: ref.watch(sessionStoreProvider).readToken),
);

/// How the phone's timezone is read. Replaceable, since tests have no
/// platform to ask.
final readTimezoneProvider = Provider<ReadTimezone>((ref) => readDeviceTimezone);

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
    await _rememberGrownUp(body);
    await _adopt(ParentSession.fromAuthResponse(body));
    unawaited(_reportTimezone());
  }

  /// [pin] is the optional "Set a 4-digit PIN" step (PA-6); null skips it.
  Future<void> registerParent({
    required String name,
    required String email,
    required String password,
    String? pin,
  }) async {
    final body = await _api.post(
      '/register',
      body: {
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': password,
        'pin': ?pin,
      },
    );
    await _rememberGrownUp(body);
    await _adopt(ParentSession.fromAuthResponse(body));
    unawaited(_reportTimezone());
  }

  /// A grown-up's PIN (PA-5), on a phone where they signed in with their
  /// password before: the ticket kept from that sign-in goes with it. A
  /// wrong PIN is an [ApiRejected] saying how many tries are left; the
  /// fifth, or a PIN that is off, an [ApiLocked] sending them to email and
  /// password.
  Future<void> signInParentWithPin({
    required String householdCode,
    required int parentId,
    required String pin,
  }) async {
    final ticket = (await _store.readGrownUps())[parentId]?.pinTicket;
    if (ticket == null) {
      throw const ApiLocked('Sign in with your email and password on this phone first.');
    }
    final body = await _api.post(
      '/parent/pin-login',
      body: {'household_code': householdCode, 'parent_id': parentId, 'pin': pin, 'pin_ticket': ticket},
    );
    await _adopt(ParentSession.fromAuthResponse(body));
    unawaited(_reportTimezone());
  }

  /// The signed-in parent showed their password again (a new PIN or a new
  /// password), and the server sent this phone a new pin ticket.
  Future<void> rememberPinTicket(String ticket) async {
    final current = state;
    if (current is! AsyncData<Session>) return;
    final session = current.value;
    if (session is! ParentSession) return;
    await _store.rememberGrownUp(session.id, email: session.email, pinTicket: ticket);
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
    unawaited(_reportTimezone());
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

  /// The signed-in parent changed their own account, and the server has
  /// already saved it. Keeps the same token.
  Future<void> adoptParentProfile(Map<String, dynamic> parent) async {
    final current = state;
    if (current is! AsyncData<Session>) return;
    final session = current.value;
    if (session is! ParentSession) return;
    final updated = session.withProfile(parent);
    // A changed email is the one to fill in next time.
    await _store.rememberGrownUp(updated.id, email: updated.email);
    await _adopt(updated);
  }

  /// The signed-in child changed their own profile, and the server has
  /// already saved it. Keeps the same token, so nothing else changes.
  Future<void> adoptChildProfile(Map<String, dynamic> child) async {
    final current = state;
    if (current is! AsyncData<Session>) return;
    final session = current.value;
    if (session is! ChildSession) return;
    await _adopt(session.withProfile(child));
  }

  /// Best effort: a household whose timezone cannot be read or sent keeps
  /// the one it has.
  Future<void> _reportTimezone() async {
    if (!ref.mounted) return;
    await TimezoneReporter(
      api: _api,
      readTimezone: ref.read(readTimezoneProvider),
    ).report();
  }

  /// After a password sign-in the phone remembers the household, so
  /// "I'm a grown-up" opens "Who are you?" next time, and this grown-up's
  /// email and pin ticket (rule 6).
  Future<void> _rememberGrownUp(Map<String, dynamic> body) async {
    final parent = body['parent'] as Map<String, dynamic>;
    await _store.writeHouseholdCode(parent['household_code'] as String);
    await _store.rememberGrownUp(
      parent['id'] as int,
      email: parent['email'] as String,
      pinTicket: body['pin_ticket'] as String?,
    );
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
      unawaited(_reportTimezone());
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
