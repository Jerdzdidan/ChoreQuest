import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/parent_notification.dart';
import '../../core/models/submission.dart';
import '../../shared/async_view.dart';
import '../../shared/avatars.dart';
import '../../shared/format.dart';
import '../../shared/submission_photo.dart';
import '../../shared/theme.dart';
import 'app_lock_alert.dart';
import 'parent_providers.dart';
import 'review_labels.dart';
import 'submission_review_screen.dart';

/// Every quest the children finished, as notifications (NT2): the ones
/// waiting for the parent on top, those to check carefully first, then the
/// alarm events (a grown-up stop, an alarm that timed out, a missing camera),
/// then the rest newest first.
///
/// Each quest is marked by how much it needs the parent's eye (PR-3), in
/// colour and icon both: Check carefully, orange with a flag; Looks genuine,
/// green with a tick; Manual check, blue with an eye. Older single photos
/// keep the marks they had.
///
/// Opening one leads to the same review screen as everywhere else, with its
/// Approve and Send back: there is no second way to decide a quest. Opening
/// the list marks everything in it seen, which clears the bell.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    // Whenever the list on screen holds something unseen, including photos
    // that arrive while it is open, the parent has now seen it. After the
    // frame, never during it: marking changes the provider this screen is
    // being built from.
    ref.listenManual<AsyncValue<NotificationFeed>>(
      notificationsProvider,
      (_, next) {
        final feed = next.value;
        if (feed != null && feed.unreadCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_markSeen()));
        }
      },
      fireImmediately: true,
    );
  }

  Future<void> _markSeen() async {
    if (_marking || !mounted) return;
    _marking = true;
    try {
      await ref.read(notificationsProvider.notifier).markSeen();
    } on ApiException {
      // The bell keeps its count until the list is next opened.
    } finally {
      _marking = false;
    }
  }

  Future<void> _open(ParentNotification item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubmissionReviewScreen(submission: item.submission)),
    );
    // A decision there changes where the photo stands here.
    if (mounted) unawaited(ref.read(notificationsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(notificationsProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            AsyncView<NotificationFeed>(
              value: feed,
              onRetry: () => ref.invalidate(notificationsProvider),
              builder: (context, loaded) {
                // Those to check carefully first, then newest first within
                // each kind: the list order otherwise.
                final waiting = [
                  for (final (i, n) in loaded.items.indexed)
                    if (n.waitsForReview) (i, n),
                ]..sort((a, b) {
                    final byUrgency = a.$2.priority.urgency.compareTo(b.$2.priority.urgency);
                    return byUrgency != 0 ? byUrgency : a.$1.compareTo(b.$1);
                  });
                final rest = [for (final n in loaded.items) if (!n.waitsForReview) n];
                if (loaded.items.isEmpty && loaded.alarms.isEmpty && loaded.missed.isEmpty && loaded.appLock.isEmpty) {
                  return const _NoPhotos();
                }
                final missedByChild = <int, List<MissedQuest>>{};
                for (final m in loaded.missed) {
                  missedByChild.putIfAbsent(m.childId, () => []).add(m);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (loaded.appLock.isNotEmpty) ...[
                      Text('App Lock', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final phone in loaded.appLock) _AppLockTile(phone: phone),
                      const SizedBox(height: 12),
                    ],
                    if (waiting.isNotEmpty) ...[
                      Text(
                        waiting.length == 1 ? '1 quest needs you' : '${waiting.length} quests need you',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final (_, item) in waiting) _NotificationTile(item: item, onOpen: () => _open(item)),
                      const SizedBox(height: 12),
                    ],
                    if (loaded.alarms.isNotEmpty) ...[
                      Text('Alarms', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final alarm in loaded.alarms) _AlarmTile(alarm: alarm),
                      const SizedBox(height: 12),
                    ],
                    if (missedByChild.isNotEmpty) ...[
                      Text('Yesterday', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final missed in missedByChild.values) _MissedTile(missed: missed),
                      const SizedBox(height: 12),
                    ],
                    if (rest.isNotEmpty) ...[
                      Text(
                        waiting.isEmpty ? 'Latest quests' : 'Everything else',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final item in rest) _NotificationTile(item: item, onOpen: () => _open(item)),
                    ],
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

/// How one quest is marked: an icon and a line that differ for each
/// priority, on a colour that differs too, so neither is needed alone to tell
/// them apart (PR-3).
(IconData, String, Tint) markFor(BuildContext context, ParentNotification item) {
  final colors = QuestColors.of(context);
  final scheme = Theme.of(context).colorScheme;
  final neutral = (fill: scheme.surfaceContainerHighest, ink: scheme.onSurfaceVariant);
  return switch (item.priority) {
    NotificationPriority.checkCarefully => (Icons.flag_rounded, 'Check carefully', colors.review),
    NotificationPriority.looksGenuine => (Icons.check_circle_rounded, 'Looks genuine', colors.approved),
    NotificationPriority.manualCheck => (Icons.visibility_rounded, 'Manual check', colors.saved),
    NotificationPriority.review => item.waitsForReview
        ? (Icons.flag_rounded, 'Needs your review', colors.review)
        : (Icons.flag_outlined, 'You checked it', neutral),
    NotificationPriority.approved => (Icons.check_circle_outline_rounded, 'Approved automatically', colors.approved),
    NotificationPriority.sentBack => (Icons.undo_rounded, 'Sent back automatically', neutral),
  };
}

/// What a quest's line says beside when it arrived: the share of real work
/// for a motion-checked session, nothing more for a manual one, and the
/// automatic check's figure for an older photo.
String? evidenceLine(ParentNotification item) {
  final s = item.submission;
  final active = s.activeSeconds;
  return switch (s.mode) {
    SessionMode.motion => active == null ? null : '${active < 60 ? '$active s' : '${active ~/ 60} min'} of real work',
    SessionMode.manual => 'Before and After photos',
    SessionMode.legacyPhoto => switch (s.confidenceDone) {
        final done? => "${formatPercent(done)} sure it's done",
        null => null,
      },
  };
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onOpen});

  final ParentNotification item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = item.submission;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, tint) = markFor(context, item);
    final line = evidenceLine(item);
    final flagged = item.waitsForReview;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: flagged ? BorderSide(color: tint.ink, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onOpen,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The routing's colour down the edge, beside its icon below.
              Container(width: 6, color: tint.ink),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox.square(
                          dimension: 64,
                          child: SubmissionPhoto(url: s.photoUrl, decodeWidth: 192),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AvatarBadge(item.childAvatar, size: 22),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.childName ?? 'Child',
                                    style: text.labelLarge,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.unread)
                                  Semantics(
                                    label: 'New',
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.choreName ?? 'Chore',
                              style: text.titleMedium?.copyWith(
                                fontWeight: item.unread ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            Text(
                              [
                                sentLabel(context, s.submittedAt),
                                ?line,
                              ].join(' · '),
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _Mark(icon: icon, label: label, tint: tint),
                                if (s.parentDecision != null) DecisionChip(submission: s),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.icon, required this.label, required this.tint});

  final IconData icon;
  final String label;
  final Tint tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: tint.fill, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tint.ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tint.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A phone where App Lock is not working now (AL-4, rule 10).
class _AppLockTile extends StatelessWidget {
  const _AppLockTile({required this.phone});

  final AppLockNotification phone;

  @override
  Widget build(BuildContext context) {
    final tint = QuestColors.of(context).review;
    final text = Theme.of(context).textTheme;
    final (IconData icon, String since) = switch (phone.trouble) {
      AppLockTrouble.needsAttention => (Icons.lock_reset_rounded, 'Since ${sentLabel(context, phone.since)}'),
      AppLockTrouble.silent => (Icons.portable_wifi_off_rounded, 'Quiet since ${sentLabel(context, phone.since)}'),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: tint.fill,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tint.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appLockLine(phone),
                    style: text.bodyMedium?.copyWith(color: tint.ink, fontWeight: phone.unread ? FontWeight.w700 : null),
                  ),
                  const SizedBox(height: 2),
                  Text(since, style: text.bodySmall?.copyWith(color: tint.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One alarm event (BE-10, DV-7, DV-12): what happened, to whom, when.
class _AlarmTile extends StatelessWidget {
  const _AlarmTile({required this.alarm});

  final AlarmNotification alarm;

  @override
  Widget build(BuildContext context) {
    final colors = QuestColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = alarm.childName;
    final chore = alarm.chore == null ? 'a quest' : alarm.chore!;
    final neutral = (fill: scheme.surfaceContainerHighest, ink: scheme.onSurfaceVariant);
    final (IconData icon, String line, Tint tint) = switch (alarm.kind) {
      AlarmEventKind.override => (
          Icons.lock_open_rounded,
          "A grown-up stopped $name's alarm for $chore with your password.",
          colors.review,
        ),
      AlarmEventKind.timedOut => (
          Icons.alarm_off_rounded,
          "$name's alarm for $chore rang as long as it may and stopped. It counts as missed, with nothing taken away.",
          neutral,
        ),
      AlarmEventKind.cameraMissing => (
          Icons.videocam_off_rounded,
          "The third-party camera wasn't connected, so $name used the phone camera for $chore.",
          colors.saved,
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: tint.fill,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tint.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line, style: text.bodyMedium?.copyWith(color: tint.ink, fontWeight: alarm.unread ? FontWeight.w700 : null)),
                  const SizedBox(height: 2),
                  Text(sentLabel(context, alarm.at), style: text.bodySmall?.copyWith(color: tint.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One child's quests missed yesterday (LS-12), said gently: a note for the
/// parent, never a penalty for the child.
class _MissedTile extends StatelessWidget {
  const _MissedTile({required this.missed});

  final List<MissedQuest> missed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final chores = [for (final m in missed) m.chore ?? 'a quest'];
    final list = switch (chores.length) {
      1 => chores.single,
      2 => '${chores[0]} and ${chores[1]}',
      _ => '${chores.sublist(0, chores.length - 1).join(', ')} and ${chores.last}',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_busy_rounded, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${missed.first.childName} didn't get to $list.",
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text('Nothing is taken away for a missed quest.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPhotos extends StatelessWidget {
  const _NoPhotos();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.notifications_none_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('Nothing yet', style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'Each quest your children finish will show up here.',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The bell for the parent's top bar (PN2): a count of what arrived since the
/// notifications were last opened, and the way into them.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(notificationsProvider);
    final unread = feed.hasValue ? feed.requireValue.unreadCount : 0;

    return IconButton(
      tooltip: switch (unread) {
        0 => 'Notifications',
        1 => '1 new notification',
        _ => '$unread new notifications',
      },
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
      icon: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        child: Icon(unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}
