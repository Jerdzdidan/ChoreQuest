import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/app_notifier.dart';
import '../../core/notifications/local_notifier.dart';
import 'parent_home_screen.dart';
import 'parent_providers.dart';
import 'review_tab.dart';

/// The parent's side of the app: their children, and the photos to review.
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
  static const _reviewTab = 1;

  var _tab = 0;
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
  /// widgets that are off screen, and a notification must not wait for the
  /// Review tab to be opened.
  void _refresh() => ref.read(reviewFeedProvider.notifier).refresh();

  /// A tapped notification: show what it was about.
  void _open(NotificationTopic topic) {
    if (!mounted) return;
    switch (topic) {
      case NotificationTopic.review:
        Navigator.of(context).popUntil((route) => route.isFirst);
        setState(() => _tab = _reviewTab);
      case NotificationTopic.outcome:
        // A child's notification. Signing out clears those, so there is
        // nothing of a child's to open from a parent's session.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(reviewFeedProvider);
    final waiting = feed.hasValue ? feed.requireValue.waiting.length : 0;

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [ParentHomeScreen(), ReviewTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom),
            label: 'Children',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: waiting,
              isLabelVisible: waiting > 0,
              child: const Icon(Icons.fact_check_outlined),
            ),
            selectedIcon: Badge.count(
              count: waiting,
              isLabelVisible: waiting > 0,
              child: const Icon(Icons.fact_check),
            ),
            label: 'Review',
            tooltip: waiting == 0
                ? 'Review'
                : waiting == 1
                    ? '1 photo to check'
                    : '$waiting photos to check',
          ),
        ],
      ),
    );
  }
}
