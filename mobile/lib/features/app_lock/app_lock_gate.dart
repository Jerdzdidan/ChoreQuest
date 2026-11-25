import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_lock/app_lock_platform.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import 'app_lock_api.dart';
import 'lock_screen.dart';

/// Around every home screen, signed in or not (AL-3, AL-6).
///
/// - At start and each return to ChoreQuest it starts App Lock's watcher
///   again if Android stopped it, and, with someone signed in, gives it the
///   server's rules for this phone. Offline, the phone keeps the rules it
///   has, so locked apps stay locked.
/// - When the watcher brings ChoreQuest up over a locked app, it opens the
///   lock screen as a route of its own on top of everything, so the back
///   button reaches the lock screen first. Leaving ChoreQuest closes it: the
///   watcher brings it back if the locked app is opened again.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  StreamSubscription<void>? _locks;
  Route<void>? _route;
  NavigatorState? _navigator;
  String? _showing;

  AppLockPlatform get _platform => ref.read(appLockPlatformProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locks = _platform.lockRequests.listen((_) => _look());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _look();
      _keepUp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locks?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _look();
        _keepUp();
      case AppLifecycleState.paused:
        _close();
      case AppLifecycleState.detached || AppLifecycleState.hidden || AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _look() async {
    final request = await _platform.pendingLock();
    if (!mounted || request == null) return;
    // Already up for this app: keep its place, such as a PIN half typed.
    if (_showing == request.package && (_route?.isActive ?? false)) return;
    _remove();
    final route = MaterialPageRoute<void>(
      builder: (_) => LockScreen(key: ValueKey(request.package), request: request),
    );
    _route = route;
    _showing = request.package;
    _navigator = Navigator.of(context);
    unawaited(_navigator!.push(route));
  }

  void _close() {
    if (_route == null) return;
    _remove();
    unawaited(_platform.clearLock());
  }

  void _remove() {
    final route = _route;
    if (route != null && route.isActive) _navigator?.removeRoute(route);
    _route = null;
    _showing = null;
  }

  Future<void> _keepUp() async {
    final on = await _platform.ensureRunning();
    if (!on || !mounted) return;
    final Session session;
    try {
      session = await ref.read(sessionProvider.future);
    } catch (_) {
      return;
    }
    if (session is SignedOut || !mounted) return;
    final key = await _platform.deviceKey();
    if (key == null) return;
    try {
      await _platform.setRules(await ref.read(appLockApiProvider).rules(key));
    } on ApiException {
      // Kept as they were: the phone's copy still locks.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
