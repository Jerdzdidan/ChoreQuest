import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alarm/alarm_safety_net.dart';
import '../../core/api/api_exception.dart';
import '../../core/camera/camera_reporter.dart';
import '../../core/device/phone_readiness.dart';
import '../../core/models/balance.dart';
import '../../core/models/child_progress.dart';
import '../../core/models/chore.dart';
import '../../core/models/submission.dart';
import '../../core/notifications/local_notifier.dart';
import '../../core/schedule/schedule_store.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/async_view.dart';
import '../../shared/format.dart';
import '../../shared/leveling.dart';
import '../../shared/theme.dart';
import 'alarm_ring_screen.dart';
import 'approval_celebration.dart';
import 'avatar_screen.dart';
import 'child_api.dart';
import 'child_providers.dart';
import 'cosmetic_unlocks.dart';
import 'family_quest_banner.dart';
import 'outcome_watcher.dart';
import 'place_quests_screen.dart';
import 'progress_card.dart';
import 'quest_list.dart';
import 'quest_log_screen.dart';
import 'quest_map.dart';
import 'quest_session_providers.dart';
import 'reward_track_screen.dart';
import 'screen_time_sheet.dart';
import 'setup_checklist_screen.dart';
import 'upload_sync.dart';

/// The child's side of the app, in four tabs (N1): Map, with their progress,
/// their screen time and the quest map of today's quests (U10); Quests, every
/// quest in one list; Avatar (U8); and Rewards, the Reward Track (T2, RW1).
///
/// Also where the child's app keeps in touch, whichever tab is open: it
/// checks for a grown-up's decisions, sends saved photos and records what the
/// child's level unlocks.
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
  late final CosmeticUnlocks _unlocks;

  /// Who this screen belongs to, fixed when it opens. The whole app is rebuilt
  /// when someone else signs in, so it never changes underneath the screen.
  ChildSession? _me;
  UploadSync? _uploads;
  bool _sendingSaved = false;
  bool _celebrating = false;

  /// Quest alarms ringing now, and when each started (DV-5, DV-7).
  StreamSubscription<Set<int>>? _ringing;
  final _ringScreens = <int>{};
  final _ringTimeouts = <int, Timer>{};

  /// Tells the server what cameras this phone has, while the app is open
  /// (DV-9).
  late final CameraReporter _cameras = ref.read(cameraReporterProvider);

  /// The last "ready for alarms" check on this phone (DV-1).
  ReadinessResult? _readiness;
  var _offeredChecklist = false;

  var _tab = 0;

  /// Tabs opened at least once. The rest are built when first opened, so a
  /// low-end phone does not load four screens at start-up. Once built, a tab
  /// stays built and keeps its scroll position.
  final _opened = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifier = ref.read(appNotifierProvider);
    _outcomes = OutcomeWatcher(
      api: ref.read(childApiProvider),
      notifier: notifier,
    );
    _unlocks = CosmeticUnlocks(ref.read(childApiProvider));
    // Whenever a refresh brings XP, record what the child's level unlocks.
    // A level already recorded costs nothing.
    ref.listenManual<AsyncValue<ChildProgress>>(
      progressProvider,
      (previous, next) {
        if (next.hasValue) {
          unawaited(_recordUnlocks(levelFor(next.requireValue.xp).level));
        }
      },
      fireImmediately: true,
    );
    final me = switch (ref.read(sessionProvider)) {
      AsyncData(value: final ChildSession session) => session,
      _ => null,
    };
    _me = me;
    // A grown-up's yes is celebrated on the child's next look (LS-10), once
    // per approval: confetti, the quest and the reward, never at sending.
    ref.listenManual<AsyncValue<List<Submission>>>(
      mySubmissionsProvider,
      (previous, next) {
        if (next.hasValue && me != null) unawaited(_celebrate(me.id, next.requireValue));
      },
      fireImmediately: true,
    );
    if (me != null) _uploads = ref.read(uploadSyncProvider(me.token));

    _startPolling();
    // The alarms follow the schedule: fetched, saved and armed now and at
    // every return to the app (DV-3); the background task does the same
    // while the app is closed. The phone's readiness is checked after, so its
    // report carries the sync just made (DV-10).
    unawaited(_syncSchedule().then((_) => _checkReadiness()));
    _ringing = ref.read(questAlarmServiceProvider).backend.ringing.listen(_onRinging, onError: (_) {});
    _cameras.start(ref.read(externalCameraSourceProvider).changes);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Photos saved while the app was closed go as soon as it opens.
      unawaited(_sendSaved());
      // Asked on the first visit, while the grown-up who set up the phone is
      // likely still beside the child. Only Android 13 and later show a
      // prompt.
      unawaited(notifier.requestPermission());
    });
  }

  Future<void> _celebrate(int childId, List<Submission> mine) async {
    if (_celebrating) return;
    _celebrating = true;
    try {
      final fresh = await ref.read(celebrationLedgerProvider).takeFresh(childId, mine);
      if (fresh.isNotEmpty && mounted) await showApprovalCelebration(context, fresh);
    } catch (_) {
      // A celebration that cannot be shown is no harm.
    } finally {
      _celebrating = false;
    }
  }

  Future<void> _syncSchedule() async {
    try {
      await ref.read(scheduleSyncProvider).sync();
    } catch (_) {
      // Offline or unhappy: the saved schedule stays armed.
    }
  }

  /// Checks what alarms need on this phone and reports it (DV-1, DV-10). The
  /// first check on a phone opens the checklist, while the grown-up who set
  /// it up is likely still there.
  Future<void> _checkReadiness() async {
    final outcome = await ref.read(phoneReadinessProvider).refresh();
    if (!mounted || outcome == null) return;
    setState(() => _readiness = outcome.result);
    // Once, even if the phone could not keep the result.
    if (outcome.firstRun && !_offeredChecklist) {
      _offeredChecklist = true;
      await _openChecklist();
    }
  }

  Future<void> _openChecklist() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SetupChecklistScreen(initial: _readiness)),
    );
    if (mounted) await _checkReadiness();
  }

  /// A quest alarm started ringing: open its ring page over whatever is on
  /// screen, and start the longest-ring clock (DV-7), counted from the
  /// alarm's own minute so a phone woken late does not ring longer.
  Future<void> _onRinging(Set<int> ids) async {
    for (final id in ids) {
      // Marked before any wait, so a second update while this one looks the
      // quest up does not open the page twice.
      if (!_ringScreens.add(id)) continue;
      final (saved, assignment) = await _lookUp(id);
      if (!mounted) return;
      if (assignment == null) {
        await _quietOffSchedule(id, saved);
        _ringScreens.remove(id);
        continue;
      }
      final since = await _ringStart(assignment);
      _armTimeout(assignment, since);
      if (!mounted) return;
      unawaited(Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => AlarmRingScreen(assignment: assignment, ringingSince: since)))
          .whenComplete(() => _ringScreens.remove(id)));
    }
    for (final id in _ringTimeouts.keys.toList()) {
      if (!ids.contains(id)) _ringTimeouts.remove(id)?.cancel();
    }
  }

  /// The ringing quest in the saved schedule. An alarm can ring before the
  /// first sync has finished, so a quest not found is looked for again after
  /// one.
  Future<(ScheduleSnapshot?, Assignment?)> _lookUp(int id) async {
    final store = ref.read(scheduleStoreProvider);
    var saved = await store.load();
    var found = saved?.assignments.where((a) => a.id == id).firstOrNull;
    if (found == null) {
      await _syncSchedule();
      saved = await store.load();
      found = saved?.assignments.where((a) => a.id == id).firstOrNull;
    }
    return (saved, found);
  }

  /// An alarm for a quest that is not on the schedule: the parent removed or
  /// paused it while it rang, so there is no quest to start and no session to
  /// stop it. It goes quiet. With no saved schedule at all to tell by, the
  /// longest ring still bounds it.
  Future<void> _quietOffSchedule(int id, ScheduleSnapshot? saved) async {
    final alarms = ref.read(questAlarmServiceProvider);
    if (saved != null) {
      await alarms.silenceOffSchedule(id, saved.assignments);
      return;
    }
    final maxMinutes = ref.read(modelConfigProvider).value?.maxRingMinutes ?? 10;
    _ringTimeouts[id]?.cancel();
    _ringTimeouts[id] = Timer(Duration(minutes: maxMinutes), () {
      _ringTimeouts.remove(id);
      unawaited(alarms.silenceOffSchedule(id, const []));
    });
  }

  Future<DateTime> _ringStart(Assignment assignment) async {
    final at = ref.read(questAlarmServiceProvider).alarmFor(assignment, after: DateTime.now().subtract(const Duration(hours: 1)))?.at;
    return at != null && at.isBefore(DateTime.now()) ? at : DateTime.now();
  }

  void _armTimeout(Assignment assignment, DateTime since) {
    _ringTimeouts[assignment.id]?.cancel();
    final maxMinutes = ref.read(modelConfigProvider).value?.maxRingMinutes ?? 10;
    final left = AlarmSafetyNet.remaining(since, maxMinutes, DateTime.now());
    _ringTimeouts[assignment.id] = Timer(left, () {
      _ringTimeouts.remove(assignment.id);
      unawaited(ref.read(alarmSafetyNetProvider).timedOut(assignment));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ringing?.cancel());
    for (final timer in _ringTimeouts.values) {
      timer.cancel();
    }
    _poll?.cancel();
    _away?.cancel();
    _cameras.stop();
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
      unawaited(_syncSchedule().then((_) => _checkReadiness()));
      _startPolling();
      _cameras.start(ref.read(externalCameraSourceProvider).changes);
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _cameras.stop();
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

  Future<void> _recordUnlocks(int level) async {
    try {
      await _unlocks.sync(level);
    } on ApiException {
      // Offline or a server fault. The next refresh tries again.
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

  void _openQuestLog() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QuestLogScreen()),
    );
  }

  void _openPlace(QuestLocation place) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaceQuestsScreen(place: place)),
    );
  }

  void _select(int tab) => setState(() {
        _tab = tab;
        _opened.add(tab);
      });

  @override
  Widget build(BuildContext context) {
    final me = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ChildSession s) => s,
      _ => null,
    };
    if (me == null) return const SizedBox.shrink();

    final title = switch (_tab) {
      1 => 'Quests',
      2 => 'My Avatar',
      3 => 'Rewards',
      _ => 'Hi, ${me.name}!',
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Switch'),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _mapTab(me),
          if (_opened.contains(1)) const _QuestsTab() else const SizedBox.shrink(),
          if (_opened.contains(2)) const AvatarScreen(showAppBar: false) else const SizedBox.shrink(),
          if (_opened.contains(3)) const RewardTrackScreen(showAppBar: false) else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag_rounded),
            label: 'Quests',
          ),
          NavigationDestination(
            icon: Icon(Icons.face_outlined),
            selectedIcon: Icon(Icons.face_rounded),
            label: 'Avatar',
          ),
          NavigationDestination(
            icon: Icon(Icons.card_giftcard_outlined),
            selectedIcon: Icon(Icons.card_giftcard_rounded),
            label: 'Rewards',
          ),
        ],
      ),
    );
  }

  /// The Map tab: progress and screen time, then the quest map (U10).
  Widget _mapTab(ChildSession me) {
    final chores = ref.watch(todayChoresProvider);
    final states = QuestStates.watch(ref, me.id);
    final balance = ref.watch(balanceProvider);
    final progress = ref.watch(progressProvider);
    final unsent = states.saved;
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        refreshChildData(ref);
        await _sendSaved();
        await ref.read(todayChoresProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // First, while any alarm row is red: nothing else on the home works
          // as it should until it is fixed.
          if (_readiness case final readiness? when !readiness.ready) ...[
            _NeedsSetupCard(readiness: readiness, onOpen: _openChecklist),
            const SizedBox(height: 12),
          ],
          ProgressCard(
            avatar: me.avatar,
            progress: progress,
            onTap: _openQuestLog,
          ),
          const SizedBox(height: 12),
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
          // Its own gap underneath when it shows, none at all when it does not.
          const FamilyQuestBanner(),
          Text('Your quest map', style: text.titleLarge),
          const SizedBox(height: 8),
          AsyncView<TodayChores>(
            value: chores,
            onRetry: () => refreshChildData(ref),
            builder: (context, today) {
              if (today.chores.isEmpty) {
                return const NothingToday('No quests today!');
              }
              return QuestMap(
                tallies: tallyByPlace(
                  today.chores,
                  (assignment) => states.of(assignment, today.date),
                ),
                onOpen: _openPlace,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The Quests tab: every quest today in one list, for a child who would
/// rather see them all at once than place by place.
class _QuestsTab extends ConsumerWidget {
  const _QuestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        refreshChildData(ref);
        await ref.read(todayChoresProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'All your quests today',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const QuestList(),
        ],
      ),
    );
  }
}

/// On the home while a "ready for alarms" row is red: what will not work,
/// and the way to the checklist, for the grown-up the child fetches.
class _NeedsSetupCard extends StatelessWidget {
  const _NeedsSetupCard({required this.readiness, required this.onOpen});

  final ReadinessResult readiness;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tint = QuestColors.of(context).review;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: tint.fill,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.alarm_off_rounded, color: tint.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Alarms may not work on this phone',
                    style: text.titleMedium?.copyWith(color: tint.ink, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${readiness.off.first.whenOff} Ask a grown-up to finish setting up.', style: text.bodyMedium?.copyWith(color: tint.ink)),
            const SizedBox(height: 10),
            FilledButton.tonal(onPressed: onOpen, child: const Text('Ready for alarms')),
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
    final ink = QuestColors.of(context).saved.ink;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: QuestColors.of(context).saved.fill,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.cloud_upload_rounded, size: 32, color: ink),
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
