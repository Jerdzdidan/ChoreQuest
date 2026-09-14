import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_progress.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/async_view.dart';
import '../../shared/badges.dart';
import '../../shared/day_bars.dart';
import '../../shared/stat_tile.dart';
import 'child_providers.dart';
import 'progress_card.dart';

/// A child's record of their quests: level and XP, their streak, the badges
/// they have earned and those still to earn, and XP day by day.
///
/// Laid out like the parent's report tab, with the same tiles and chart, so
/// the two sides of the app read as one.
class QuestLogScreen extends ConsumerWidget {
  const QuestLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ChildSession s) => s,
      _ => null,
    };
    if (me == null) return const SizedBox.shrink();

    final progress = ref.watch(progressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My quest log')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(progressProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            ProgressCard(avatar: me.avatar, progress: progress),
            const SizedBox(height: 24),
            AsyncView<ChildProgress>(
              value: progress,
              onRetry: () => ref.invalidate(progressProvider),
              builder: (context, value) => _Log(progress: value),
            ),
          ],
        ),
      ),
    );
  }
}

class _Log extends StatelessWidget {
  const _Log({required this.progress});

  final ChildProgress progress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = progress;
    final earned = p.badges.where((badge) => badge.earned).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Streak', style: text.titleMedium),
        const SizedBox(height: 8),
        StatTilePair(
          left: StatTile(
            label: 'Days in a row',
            value: '${p.currentStreak}',
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFD9480F),
          ),
          right: StatTile(
            label: 'Best ever',
            value: '${p.bestStreak}',
            icon: Icons.star_rounded,
            iconColor: const Color(0xFFE0A100),
          ),
        ),
        const SizedBox(height: 24),
        Text('Badges', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          switch (earned) {
            0 => 'No badges yet. Finish your first quest to earn one!',
            1 => 'You have earned 1 badge.',
            _ => 'You have earned $earned badges.',
          },
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        for (final badge in p.badges) _BadgeRow(badge: badge),
        const SizedBox(height: 14),
        Text('XP in the last two weeks', style: text.titleMedium),
        const SizedBox(height: 8),
        DayBars(days: p.history, describe: (xp) => '$xp XP'),
      ],
    );
  }
}

/// One badge: bright with the day it was earned, or pale with how far there
/// is still to go.
class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.badge});

  final BadgeStatus badge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = badgeStyleFor(badge.key);
    final earnedAt = badge.earnedAt;
    final earned = earnedAt != null;
    final fraction = badge.target <= 0 ? 0.0 : badge.progress / badge.target;
    final progressLabel = style.progressLabel(badge.progress, badge.target);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: earned ? style.background : scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: earned ? Colors.white : scheme.surfaceContainerHighest,
              ),
              child: Icon(
                style.icon,
                size: 30,
                color: earned ? style.ink : scheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    style.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: earned ? style.ink : null,
                    ),
                  ),
                  Text(
                    style.goal(badge.target),
                    style: text.bodyMedium?.copyWith(
                      color: earned ? style.ink : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (earned)
                    Text(
                      'Earned ${MaterialLocalizations.of(context).formatShortMonthDay(earnedAt.toLocal())}',
                      style: text.labelLarge?.copyWith(
                        color: style.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 8,
                        backgroundColor: scheme.surfaceContainerHighest,
                        // A progress bar's spoken value must be a number from
                        // 0 to 100; the words go in the label.
                        semanticsLabel: '${style.title}: $progressLabel',
                        semanticsValue: '${(fraction * 100).round()}',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progressLabel,
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
