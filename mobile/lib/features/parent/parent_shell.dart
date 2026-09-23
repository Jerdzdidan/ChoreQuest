import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/app_notifier.dart';
import '../../core/notifications/local_notifier.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/avatars.dart';
import 'activity_screen.dart';
import 'child_form_screen.dart';
import 'notifications_screen.dart';
import 'parent_home_screen.dart';
import 'parent_profile_screen.dart';
import 'parent_providers.dart';
import 'quest_catalogue_screen.dart';

/// The parent's side of the app, in four tabs (PN1): Board, with each child's
/// caps and quests to give out; Quests, the whole catalogue; Activity, how one
/// child is doing; and Profile, their own account and their children's.
///
/// The bar above them carries their picture, which opens Profile, and the bell
/// with its count of new photos (PN2). Photos waiting for a decision are
/// reached from the bell and from the Board, so there is no Review tab.
///
/// Also where a parent hears about new photos. The review lists refresh every
/// 30 seconds while the app is on screen, and every minute in the background
/// for as long as Android keeps the app running; anything new is announced as
/// a notification.
class ParentShell extends ConsumerStatefulWidget {
  const ParentShell({super.key});

  @override
  ConsumerState<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends ConsumerState<ParentShell>
    with WidgetsBindingObserver {
  static const _board = 0;
  static const _quests = 1;
  static const _activity = 2;
  static const _profile = 3;

  var _tab = _board;

  /// Tabs opened at least once. The rest are built when first opened, so
  /// signing in loads one screen rather than four. Once built, a tab stays
  /// built and keeps its scroll position.
  final _opened = <int>{_board};

  Timer? _poll;
  StreamSubscription<NotificationTopic>? _taps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifier = ref.read(appNotifierProvider);
    _taps = notifier.taps.listen(_open);
    _pollEvery(const Duration(seconds: 30));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final opened = await notifier.takeLaunchTopic();
      if (opened != null) _open(opened);
      await notifier.requestPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _taps?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _pollEvery(const Duration(seconds: 30));
    } else if (state == AppLifecycleState.paused) {
      _pollEvery(const Duration(minutes: 1));
    }
  }

  void _pollEvery(Duration interval) {
    _poll?.cancel();
    _poll = Timer.periodic(interval, (_) => _refresh());
  }

  /// A plain call rather than a listener: Riverpod pauses the subscriptions of
  /// widgets that are off screen, and a notification must not wait for a tab
  /// to be opened. The bell's count comes along on the same beat.
  void _refresh() {
    ref.read(reviewFeedProvider.notifier).refresh();
    ref.read(notificationsProvider.notifier).refresh();
  }

  void _select(int tab) => setState(() {
        _tab = tab;
        _opened.add(tab);
      });

  /// A tapped notification: show what it was about.
  void _open(NotificationTopic topic) {
    if (!mounted) return;
    switch (topic) {
      case NotificationTopic.review:
        Navigator.of(context).popUntil((route) => route.isFirst);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
      case NotificationTopic.outcome:
        // A child's notification. Signing out clears those, so there is
        // nothing of a child's to open from a parent's session.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ParentSession s) => s,
      _ => null,
    };
    if (parent == null) return const SizedBox.shrink();

    // Kept loaded for as long as a parent is signed in, so the bell's count
    // and the Board's waiting card are there whichever tab is open.
    ref.listen(notificationsProvider, (_, _) {});
    ref.listen(reviewFeedProvider, (_, _) {});

    final title = switch (_tab) {
      _quests => 'Quests',
      _activity => 'Activity',
      _profile => 'Profile',
      _ => 'Parent Board',
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Your profile',
          onPressed: () => _select(_profile),
          icon: AvatarBadge(parent.avatar, size: 32),
        ),
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: const [NotificationBell()],
      ),
      floatingActionButton: _tab == _board
          ? FloatingActionButton.extended(
              heroTag: 'add-child',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChildFormScreen()),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add child'),
            )
          : null,
      // One stack, so each tab keeps its scroll position while another is
      // shown.
      body: IndexedStack(
        index: _tab,
        children: [
          const ParentHomeScreen(),
          if (_opened.contains(_quests)) const QuestCatalogueScreen(showAppBar: false) else const SizedBox.shrink(),
          if (_opened.contains(_activity)) const ActivityScreen(showAppBar: false) else const SizedBox.shrink(),
          if (_opened.contains(_profile)) const ParentProfileScreen() else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'Board',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag_rounded),
            label: 'Quests',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
