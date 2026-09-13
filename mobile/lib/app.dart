import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/session/session.dart';
import 'core/session/session_controller.dart';
import 'features/auth/welcome_screen.dart';
import 'features/child/child_home_screen.dart';
import 'features/parent/parent_shell.dart';
import 'shared/theme.dart';

/// The root. Decides which of three worlds the device is in: signed out, a
/// parent's, or a child's.
///
/// The MaterialApp is keyed by who is signed in. When that changes, Flutter
/// discards the entire navigation stack and starts clean, so a PIN screen can
/// never be left sitting on top of a child's freshly opened home, and nothing
/// a parent opened can survive into a child's session on the same phone. The
/// guarantee holds without every sign-in and sign-out remembering to pop
/// routes, which over sixteen slices someone eventually would forget.
class ChoreQuestApp extends ConsumerWidget {
  const ChoreQuestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (String identity, Widget home) = switch (ref.watch(sessionProvider)) {
      AsyncData(value: ParentSession(:final id)) => (
          'parent-$id',
          const ParentShell(),
        ),
      AsyncData(value: ChildSession(:final id)) => (
          'child-$id',
          const ChildHomeScreen(),
        ),
      AsyncData(value: SignedOut()) => ('signed-out', const WelcomeScreen()),
      AsyncError() => ('signed-out', const WelcomeScreen()),
      AsyncLoading() => ('restoring', const _Restoring()),
    };

    return MaterialApp(
      key: ValueKey(identity),
      title: 'ChoreQuest',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: home,
    );
  }
}

class _Restoring extends StatelessWidget {
  const _Restoring();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
