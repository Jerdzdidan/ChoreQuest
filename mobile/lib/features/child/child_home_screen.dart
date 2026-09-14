import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/balance.dart';
import '../../core/models/chore.dart';
import '../../core/models/submission.dart';
import '../../core/notifications/local_notifier.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../core/uploads/pending_upload.dart';
import '../../shared/async_view.dart';
import '../../shared/avatars.dart';
import '../../shared/format.dart';
import 'child_api.dart';
import 'child_providers.dart';
import 'chore_camera_screen.dart';
import 'chore_card.dart';
import 'outcome_watcher.dart';
import 'screen_time_sheet.dart';
import 'upload_sync.dart';

/// The child's home: their screen time, and today's chores as big cards.
class ChildHomeScreen extends ConsumerStatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  ConsumerState<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends ConsumerState<ChildHomeScreen>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _away;
  late final OutcomeWatcher _outcomes;

  /// Who this screen belongs to, fixed when it opens. The whole app is rebuilt
  /// when someone else signs in, so it never changes underneath the screen.
  ChildSession? _me;
  UploadSync? _uploads;
  bool _sendingSaved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifier = ref.read(appNotifierProvider);
    _outcomes = OutcomeWatcher(
      api: ref.read(childApiProvider),
      notifier: notifier,
    );
    final me = switch (ref.read(sessionProvider)) {
      AsyncData(value: final ChildSession session) => session,
      _ => null,
    };
    _me = me;
    if (me != null) _uploads = ref.read(uploadSyncProvider(me.token));

    _startPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Photos saved while the app was closed go as soon as it opens.
      unawaited(_sendSaved());
      // Asked on the first visit, while the grown-up who set up the phone is
      // likely still beside the child. Only Android 13 and later show a
      // prompt.
      unawaited(notifier.requestPermission());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _away?.cancel();
    super.dispose();
  }

  /// A grown-up can approve a photo at any moment, so check back while the
  /// child is looking -- and only then, to spare the battery on a low-end
  /// phone left sitting on this screen. Saved photos get another try on the
  /// same beat.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      refreshChildData(ref);
      unawaited(_sendSaved());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _away?.cancel();
      refreshChildData(ref);
      unawaited(_sendSaved());
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _watchWhileAway();
    }
  }

  /// Away from the app, saved photos keep trying to send, and a grown-up's
  /// decision arrives as a notification. The phone keeps at it only while a
  /// photo is still waiting, for a connection or for a grown-up, and stops as
  /// soon as none is, to spare the battery.
  ///
  /// Driven by a timer and plain calls, not by the providers: Riverpod pauses
  /// this screen's subscriptions whenever another screen covers it.
  void _watchWhileAway() {
    _outcomes.reset();
    _away?.cancel();
    _away = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _lookWhileAway(),
    );
    unawaited(_lookWhileAway());
  }

  Future<void> _lookWhileAway() async {
    final unsent = await _sendSaved();
    try {
      final stillWaiting = await _outcomes.look();
      if (!stillWaiting && unsent == 0) _away?.cancel();
    } on ApiUnauthorised {
      // Signed out on the server. Saved photos wait for the next sign-in.
      _away?.cancel();
    } on ApiException {
      // No connection. The next tick tries again.
    }
  }

  /// Sends photos saved while the phone was offline, and returns how many are
  /// still waiting. Cheap when there are none, and a call while a send is
  /// already running joins it instead of sending anything twice.
  Future<int> _sendSaved() async {
    final me = _me;
    final uploads = _uploads;
    if (me == null || uploads == null) return 0;
    try {
      final results = await uploads.flush(childId: me.id);
      final settled =
          results.any((result) => result.outcome != UploadOutcome.waiting);
      if (settled && mounted) refreshChildData(ref);
      return (await uploads.queue.forChild(me.id)).length;
    } on FileSystemException {
      // The list of saved photos could not be read; nothing to send until it
      // can be.
      return 0;
    }
  }

  Future<void> _sendNow() async {
    setState(() => _sendingSaved = true);
    final left = await _sendSaved();
    if (!mounted) return;
    setState(() => _sendingSaved = false);
    if (left > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Still can't send. Your photos are saved.")),
      );
    }
  }

  Future<void> _openCamera(Assignment assignment) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChoreCameraScreen(assignment: assignment),
      ),
    );
    if (mounted) refreshChildData(ref);
  }

  @override
  Widget build(BuildContext context) {
    final me = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ChildSession s) => s,
      _ => null,
    };
    if (me == null) return const SizedBox.shrink();

    final chores = ref.watch(todayChoresProvider);
    final submissions = ref.watch(mySubmissionsProvider);
    final balance = ref.watch(balanceProvider);
    final saved = ref.watch(pendingUploadsProvider(me.id));
    final unsent =
        saved.hasValue ? saved.requireValue : const <PendingUpload>[];
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            AvatarBadge(me.avatar, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Hi, ${me.name}!', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Switch'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshChildData(ref);
          await _sendSaved();
          await ref.read(todayChoresProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _ScreenTimeCard(balance: balance),
            if (unsent.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SavedPhotosCard(
                count: unsent.length,
                sending: _sendingSaved,
                onSend: _sendNow,
              ),
            ],
            const SizedBox(height: 20),
            Text('Your quests today', style: text.titleLarge),
            const SizedBox(height: 8),
            AsyncView<TodayChores>(
              value: chores,
              onRetry: () => refreshChildData(ref),
              builder: (context, today) {
                if (today.chores.isEmpty) return const _NothingToday();

                final sent = submissions.hasValue
                    ? submissions.requireValue
                    : const <Submission>[];
                final perPoint = balance.hasValue
                    ? balance.requireValue.minutesPerPoint
                    : null;

                return Column(
                  children: [
                    for (final assignment in today.chores)
                      ChoreCard(
                        assignment: assignment,
                        state: choreStateFor(
                          assignment,
                          sent,
                          today.date,
                          saved: unsent,
                        ),
                        minutesPerPoint: perPoint,
                        onTap: () => _openCamera(assignment),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenTimeCard extends StatelessWidget {
  const _ScreenTimeCard({required this.balance});

  final AsyncValue<Balance> balance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final value = balance.hasValue ? balance.requireValue : null;
    final canSpend = value != null && value.spendableMinutes > 0;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 44, color: scheme.onPrimaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Screen time',
                    style: text.labelLarge
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                  Text(
                    value == null ? '...' : formatMinutes(value.spendableMinutes),
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  if (value != null && value.earningBlocked)
                    Text(
                      "That's all you can earn for now.",
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: canSpend ? () => showScreenTimeSheet(context, value) : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Use'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Photos taken while the phone was offline. They send by themselves; the
/// button is for a grown-up who knows the connection is back.
class _SavedPhotosCard extends StatelessWidget {
  const _SavedPhotosCard({
    required this.count,
    required this.sending,
    required this.onSend,
  });

  final int count;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1D4A73);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: const Color(0xFFDCE6F2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.cloud_upload_rounded, size: 32, color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == 1
                    ? '1 photo is saved and will send soon.'
                    : '$count photos are saved and will send soon.',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: ink),
              ),
            ),
            const SizedBox(width: 8),
            if (sending)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else
              TextButton(onPressed: onSend, child: const Text('Send now')),
          ],
        ),
      ),
    );
  }
}

class _NothingToday extends StatelessWidget {
  const _NothingToday();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.wb_sunny_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'No quests today!',
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
