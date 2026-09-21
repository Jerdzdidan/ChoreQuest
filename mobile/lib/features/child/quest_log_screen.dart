import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_progress.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/async_view.dart';
import '../../shared/day_bars.dart';
import '../../shared/stat_tile.dart';
import '../../shared/theme.dart';
import 'badge_list.dart';
import 'child_providers.dart';
import 'choose_avatar_screen.dart';
import 'progress_card.dart';
import 'story_list.dart';

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
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChooseAvatarScreen()),
              ),
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
              icon: const Icon(Icons.pets_rounded),
              label: const Text('Change my animal'),
            ),
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
            iconColor: QuestColors.of(context).flame,
          ),
          right: StatTile(
            label: 'Best ever',
            value: '${p.bestStreak}',
            icon: Icons.star_rounded,
            iconColor: QuestColors.of(context).xpStar,
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
        BadgeList(badges: p.badges),
        const SizedBox(height: 14),
        Text('Your story', style: text.titleMedium),
        const SizedBox(height: 8),
        StoryList(progress: p),
        const SizedBox(height: 14),
        Text('XP in the last two weeks', style: text.titleMedium),
        const SizedBox(height: 8),
        DayBars(days: p.history, describe: (xp) => '$xp XP'),
      ],
    );
  }
}
