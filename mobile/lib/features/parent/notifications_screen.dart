import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/parent_notification.dart';
import '../../shared/async_view.dart';
import '../../shared/avatars.dart';
import '../../shared/format.dart';
import '../../shared/submission_photo.dart';
import '../../shared/theme.dart';
import 'parent_providers.dart';
import 'review_labels.dart';
import 'submission_review_screen.dart';

/// Every photo the children sent, as notifications (NT2): the ones the
/// checker left to a grown-up on top, under an orange flag, and the rest
/// newest first, the checker's approvals with a green tick.
///
/// Opening one leads to the same review screen as everywhere else, with its
/// Approve and Send back: there is no second way to decide a photo. Opening
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
                final waiting = [for (final n in loaded.items) if (n.waitsForReview) n];
                final rest = [for (final n in loaded.items) if (!n.waitsForReview) n];
                if (loaded.items.isEmpty) return const _NoPhotos();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (waiting.isNotEmpty) ...[
                      Text(
                        waiting.length == 1 ? '1 photo needs you' : '${waiting.length} photos need you',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final item in waiting) _NotificationTile(item: item, onOpen: () => _open(item)),
                      const SizedBox(height: 12),
                    ],
                    if (rest.isNotEmpty) ...[
                      Text(
                        waiting.isEmpty ? 'Latest photos' : 'Everything else',
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

/// How one photo is marked: an icon and a line that differ for each routing,
/// on a colour that differs too, so neither is needed alone to tell them
/// apart.
(IconData, String, Tint) markFor(BuildContext context, ParentNotification item) {
  final colors = QuestColors.of(context);
  final scheme = Theme.of(context).colorScheme;
  final neutral = (fill: scheme.surfaceContainerHighest, ink: scheme.onSurfaceVariant);
  return switch (item.priority) {
    NotificationPriority.review => item.waitsForReview
        ? (Icons.flag_rounded, 'Needs your review', colors.review)
        : (Icons.flag_outlined, 'You checked it', neutral),
    NotificationPriority.approved => (Icons.check_circle_rounded, 'Approved by the checker', colors.approved),
    NotificationPriority.sentBack => (Icons.undo_rounded, 'Sent back by the checker', neutral),
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
    final confidence = s.confidenceDone;
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
                                if (confidence != null) "${formatPercent(confidence)} sure it's done",
                              ].join(' · '),
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            _Mark(icon: icon, label: label, tint: tint),
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
            'Each photo your children send will show up here.',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The bell for the parent's top bar (PN2): a count of photos sent since the
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
        1 => '1 new photo',
        _ => '$unread new photos',
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
