import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_lock/app_lock_platform.dart';
import '../../core/session/session_controller.dart';
import '../../core/session/session_store.dart';
import '../../shared/avatars.dart';
import '../../shared/inline_error.dart';
import '../../shared/password_field.dart';
import '../auth/household_api.dart';
import '../auth/pin_pad.dart';
import '../auth/profile_tile.dart';
import 'app_lock_api.dart';

/// "Who's using {app}?" (AL-6): the screen App Lock brings up over a locked
/// app.
///
/// - A child picks their face and types their PIN. The server spends their
///   first minute, which records the unlock, and the watcher spends each
///   minute after it while the app is open. With no minutes: "No time left
///   yet. Finish a quest to earn more."
/// - A grown-up picks their face and types their PIN, or their password when
///   their PIN is off or this phone has not seen their password. The unlock
///   is recorded before the app opens (rule 10).
/// - Grown-ups only apps show the children's faces dimmed.
///
/// Each unlock signs its person in for that unlock only: whoever is signed in
/// on the phone stays signed in. Without the server nothing opens (rule 9).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.request});

  final LockRequest request;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

/// What the lock screen needs before it can show anyone.
class _LockData {
  const _LockData({
    required this.householdCode,
    required this.deviceKey,
    required this.roster,
    required this.known,
    this.icon,
  });

  final String householdCode;
  final String deviceKey;
  final HouseholdRoster roster;
  final Map<int, KnownGrownUp> known;
  final Uint8List? icon;
}

class _NotPaired implements Exception {
  const _NotPaired();
}

sealed class _Step {
  const _Step();
}

class _Who extends _Step {
  const _Who();
}

class _ChildPin extends _Step {
  const _ChildPin(this.child);
  final RosterChild child;
}

class _GrownUpPin extends _Step {
  const _GrownUpPin(this.parent);
  final RosterParent parent;
}

class _GrownUpPassword extends _Step {
  const _GrownUpPassword(this.parent, {this.notice});
  final RosterParent parent;
  final String? notice;
}

class _LockScreenState extends ConsumerState<LockScreen> {
  late Future<_LockData> _load = _fetch();
  _Step _step = const _Who();
  String? _notice;
  bool _leaving = false;

  AppLockPlatform get _platform => ref.read(appLockPlatformProvider);
  AppLockApi get _api => ref.read(appLockApiProvider);
  LockRequest get _request => widget.request;
  bool get _grownUpsOnly => _request.setting == AppSetting.grownUpsOnly;

  Future<_LockData> _fetch() async {
    final store = ref.read(sessionStoreProvider);
    final code = await store.readHouseholdCode();
    if (code == null) throw const _NotPaired();
    final deviceKey = await _platform.deviceKey();
    if (deviceKey == null) throw const _NotPaired();
    final roster = await fetchHouseholdRoster(ref.read(clientForTokenProvider)(null), code);
    return _LockData(
      householdCode: code,
      deviceKey: deviceKey,
      roster: roster,
      known: await store.readGrownUps(),
      icon: await _platform.appIcon(_request.package),
    );
  }

  /// Leaves the locked app behind, unopened.
  Future<void> _goHome() async {
    if (_leaving) return;
    _leaving = true;
    await _platform.clearLock();
    await _platform.goHome();
  }

  void _back() {
    if (_step is _Who) {
      _goHome();
    } else {
      setState(() => _step = const _Who());
    }
  }

  Future<String?> _childPin(_LockData data, RosterChild child, String pin) async {
    final String token;
    try {
      token = await _api.childToken(householdCode: data.householdCode, childId: child.id, pin: pin);
    } on ApiException catch (e) {
      return e.message;
    }
    try {
      final balance = await _api.openWithMinute(token: token, deviceKey: data.deviceKey, package: _request.package);
      await _platform.startChildSession(package: _request.package, token: token, balanceAfter: balance);
    } on ApiRejected catch (e) {
      await _api.signOut(token);
      if (e.statusCode == 409) {
        if (mounted) {
          setState(() {
            _step = const _Who();
            _notice = 'No time left yet. Finish a quest to earn more.';
          });
        }
        return null;
      }
      return e.message;
    } on ApiException catch (e) {
      await _api.signOut(token);
      return e.message;
    }
    await _open();
    return null;
  }

  Future<String?> _grownUpPin(_LockData data, RosterParent parent, String pin) async {
    final ticket = data.known[parent.id]?.pinTicket;
    if (ticket == null) {
      _usePassword(parent, 'Use your password this time. Your PIN will work here after that.');
      return null;
    }
    try {
      final pass = await _api.grownUpWithPin(
        householdCode: data.householdCode,
        parentId: parent.id,
        pin: pin,
        pinTicket: ticket,
      );
      return await _grownUpUnlock(data, pass.token);
    } on ApiLocked catch (e) {
      _usePassword(parent, e.message);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> _grownUpPassword(_LockData data, RosterParent parent, String email, String password) async {
    final GrownUpPass pass;
    try {
      pass = await _api.grownUpWithPassword(email: email, password: password);
    } on ApiException catch (e) {
      return e.message;
    }
    if (pass.parentId != parent.id) {
      await _api.signOut(pass.token);
      return "That email is not ${parent.name}'s.";
    }
    // Their password, typed here: their PIN now works on this phone too.
    await ref.read(sessionStoreProvider).rememberGrownUp(parent.id, email: email, pinTicket: pass.pinTicket);
    return _grownUpUnlock(data, pass.token);
  }

  /// Rule 10: the unlock is recorded before the app opens.
  Future<String?> _grownUpUnlock(_LockData data, String token) async {
    try {
      await _api.recordGrownUpUnlock(token: token, deviceKey: data.deviceKey, package: _request.package);
    } on ApiException catch (e) {
      return e.message;
    } finally {
      await _api.signOut(token);
    }
    await _platform.allowGrownUp(_request.package);
    await _open();
    return null;
  }

  Future<void> _open() async {
    _leaving = true;
    final opened = await _platform.openApp(_request.package);
    if (!opened) {
      await _platform.clearLock();
      await _platform.goHome();
    }
  }

  void _usePassword(RosterParent parent, String? notice) {
    if (mounted) setState(() => _step = _GrownUpPassword(parent, notice: notice));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: FutureBuilder(
            future: _load,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final error = snapshot.error;
              if (error != null) return _cannotOpen(error);
              final data = snapshot.requireData;
              return switch (_step) {
                _Who() => _who(data),
                _ChildPin(:final child) => _pinPad(
                    avatar: child.avatar,
                    name: child.name,
                    hint: 'Type your PIN to use your earned time',
                    onComplete: (pin) => _childPin(data, child, pin),
                  ),
                _GrownUpPin(:final parent) => _pinPad(
                    avatar: parent.avatar,
                    name: parent.name,
                    hint: 'Type your PIN to open ${_request.label}',
                    onComplete: (pin) => _grownUpPin(data, parent, pin),
                    footer: TextButton(
                      onPressed: () => _usePassword(parent, null),
                      child: const Text('Use my password instead'),
                    ),
                  ),
                _GrownUpPassword(:final parent, :final notice) => _PasswordStep(
                    key: ValueKey(parent.id),
                    parent: parent,
                    appLabel: _request.label,
                    email: data.known[parent.id]?.email,
                    notice: notice,
                    onBack: _back,
                    onSubmit: (email, password) => _grownUpPassword(data, parent, email, password),
                  ),
              };
            },
          ),
        ),
      ),
    );
  }

  Widget _pinPad({
    required String avatar,
    required String name,
    required String hint,
    required Future<String?> Function(String pin) onComplete,
    Widget? footer,
  }) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BackButton(onPressed: _back),
        ),
        Expanded(
          child: PinPad(
            header: PinHeader(avatar: AvatarBadge(avatar, size: 96), name: name, hint: hint),
            onComplete: onComplete,
            footer: footer,
          ),
        ),
      ],
    );
  }

  Widget _who(_LockData data) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final label = _request.label;
    final banner = switch (_request.reason) {
      LockReason.timeUp => "Time's up on $label.",
      LockReason.offline => "ChoreQuest couldn't reach the server, so $label locked. It stays locked until ChoreQuest can.",
      LockReason.locked => null,
    };
    final notice = _notice;
    final icon = data.icon;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        Center(
          child: icon == null
              ? Icon(Icons.lock_rounded, size: 56, color: scheme.primary)
              : Image.memory(icon, width: 64, height: 64, semanticLabel: label),
        ),
        const SizedBox(height: 12),
        Text(
          "Who's using $label?",
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          _grownUpsOnly ? 'This app is for grown-ups only.' : 'It opens with earned time, or a grown-up\'s PIN.',
          textAlign: TextAlign.center,
          style: text.bodyLarge,
        ),
        if (banner != null) ...[
          const SizedBox(height: 16),
          _Banner(banner),
        ],
        if (notice != null) ...[
          const SizedBox(height: 16),
          _Banner(notice),
        ],
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: data.roster.children.length + data.roster.parents.length,
          itemBuilder: (context, i) {
            final children = data.roster.children;
            if (i < children.length) {
              final child = children[i];
              final tile = ProfileTile(
                avatar: child.avatar,
                name: child.name,
                onTap: () => setState(() {
                  _notice = null;
                  _step = _ChildPin(child);
                }),
              );
              if (!_grownUpsOnly) return tile;
              return Semantics(
                label: '${child.name}, grown-ups only',
                excludeSemantics: true,
                child: Opacity(opacity: 0.35, child: IgnorePointer(child: tile)),
              );
            }
            final parent = data.roster.parents[i - children.length];
            return ProfileTile(
              avatar: parent.avatar,
              name: parent.name,
              onTap: () => setState(() {
                _notice = null;
                final canPin = parent.pin && data.known[parent.id]?.pinTicket != null;
                _step = canPin ? _GrownUpPin(parent) : _GrownUpPassword(parent);
              }),
            );
          },
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: _goHome, child: const Text('Not now')),
      ],
    );
  }

  Widget _cannotOpen(Object error) {
    final message = switch (error) {
      _NotPaired() => 'This phone is not set up with a household. A grown-up can sign in to ChoreQuest here to set it up.',
      ApiException() => "ChoreQuest can't reach the server, so ${_request.label} stays locked until it can.",
      _ => "${_request.label} stays locked. Try again in a moment.",
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.lock_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        InlineError(message),
        const SizedBox(height: 16),
        if (error is! _NotPaired)
          FilledButton(
            onPressed: () => setState(() => _load = _fetch()),
            child: const Text('Try again'),
          ),
        const SizedBox(height: 8),
        TextButton(onPressed: _goHome, child: const Text('Not now')),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }
}

/// A grown-up's password, when their PIN cannot be used here.
class _PasswordStep extends StatefulWidget {
  const _PasswordStep({
    super.key,
    required this.parent,
    required this.appLabel,
    required this.email,
    required this.notice,
    required this.onBack,
    required this.onSubmit,
  });

  final RosterParent parent;
  final String appLabel;
  final String? email;
  final String? notice;
  final VoidCallback onBack;
  final Future<String?> Function(String email, String password) onSubmit;

  @override
  State<_PasswordStep> createState() => _PasswordStepState();
}

class _PasswordStepState extends State<_PasswordStep> {
  late final _email = TextEditingController(text: widget.email ?? '');
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Type your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(email, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final notice = widget.notice;
    final error = _error;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Align(alignment: Alignment.centerLeft, child: BackButton(onPressed: widget.onBack)),
        PinHeader(
          avatar: AvatarBadge(widget.parent.avatar, size: 80),
          name: widget.parent.name,
          hint: 'Type your password to open ${widget.appLabel}',
        ),
        if (notice != null) ...[
          const SizedBox(height: 16),
          _Banner(notice),
        ],
        const SizedBox(height: 20),
        if (widget.email == null) ...[
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(widget.email!, textAlign: TextAlign.center, style: text.titleMedium),
          ),
        PasswordField(
          controller: _password,
          autofocus: true,
          enabled: !_busy,
          errorText: error,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text('Open ${widget.appLabel}'),
        ),
      ],
    );
  }
}
