import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_activity.dart';
import '../../core/models/child_profile.dart';
import '../../shared/async_view.dart';
import '../../shared/avatars.dart';
import '../../shared/format.dart';
import '../../shared/leveling.dart';
import '../../shared/stat_tile.dart';
import '../../shared/theme.dart';
import '../../shared/xp_bar.dart';
import 'parent_providers.dart';

/// How one child is doing (ACT1): how much of what they were given got done,
/// their streak, their level, and the screen time they have earned this week.
///
/// With more than one child, a picker at the top chooses whose figures these
/// are. Every figure comes from one answer for that child, so choosing
/// another changes all of them together rather than some now and some later.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, this.showAppBar = true});

  /// False when the screen is the Activity tab, under the shell's own bar.
  final bool showAppBar;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  int? _childId;

  /// The child being shown: the one chosen, while they are still in the
  /// household, or else the first.
  ChildProfile? _chosen(List<ChildProfile> children) {
    if (children.isEmpty) return null;
    for (final child in children) {
      if (child.id == _childId) return child;
    }
    return children.first;
  }

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(childrenProvider);
    final text = Theme.of(context).textTheme;

    final body = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(childrenProvider);
        final chosen = _chosen(children.value ?? const []);
        if (chosen != null) ref.invalidate(activityProvider(chosen.id));
        await ref.read(childrenProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AsyncView<List<ChildProfile>>(
            value: children,
            onRetry: () => ref.invalidate(childrenProvider),
            builder: (context, list) {
              final chosen = _chosen(list);
              if (chosen == null) {
                return Text(
                  'Add a child to see how they are doing.',
                  style: text.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (list.length > 1) ...[
                    _ChildPicker(
                      children: list,
                      chosen: chosen,
                      onPick: (child) => setState(() => _childId = child.id),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _Figures(child: chosen),
                ],
              );
            },
          ),
        ],
      ),
    );

    if (!widget.showAppBar) return body;
    return Scaffold(appBar: AppBar(title: const Text('Activity')), body: body);
  }
}

class _ChildPicker extends StatelessWidget {
  const _ChildPicker({required this.children, required this.chosen, required this.onPick});

  final List<ChildProfile> children;
  final ChildProfile chosen;
  final ValueChanged<ChildProfile> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final child in children)
          ChoiceChip(
            selected: child.id == chosen.id,
            onSelected: (_) => onPick(child),
            avatar: AvatarBadge(child.avatar, size: 24),
            label: Text(child.name, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

class _Figures extends ConsumerWidget {
  const _Figures({required this.child});

  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityProvider(child.id));

    return AsyncView<ChildActivity>(
      value: activity,
      onRetry: () => ref.invalidate(activityProvider(child.id)),
      builder: (context, figures) => _Dashboard(figures: figures),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.figures});

  final ChildActivity figures;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = QuestColors.of(context);
    final level = levelFor(figures.xp);
    final rate = figures.completion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: 'Quests done',
          tint: colors.approved,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rate == null ? 'No quests yet' : formatPercent(rate),
                style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: colors.approved.ink),
              ),
              Text(
                rate == null
                    ? 'Give ${figures.childName} a quest to start.'
                    : '${figures.questsDone} of ${figures.questsDue} quests in the last ${figures.completionDays} days',
                style: text.bodyMedium?.copyWith(color: colors.approved.ink),
              ),
              if (rate != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 10,
                    color: colors.approved.ink,
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        StatTilePair(
          left: StatTile(
            label: 'Streak',
            value: figures.currentStreak == 1 ? '1 day' : '${figures.currentStreak} days',
            icon: Icons.local_fire_department_rounded,
            iconColor: colors.flame,
          ),
          right: StatTile(
            label: 'Best streak',
            value: figures.bestStreak == 1 ? '1 day' : '${figures.bestStreak} days',
          ),
        ),
        const SizedBox(height: 10),
        _Panel(
          title: 'Level',
          tint: colors.xp,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Level ${level.level}',
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: colors.xp.ink),
              ),
              const SizedBox(height: 8),
              XpBar(xp: figures.xp),
              const SizedBox(height: 6),
              Text(
                '${figures.xp} XP · ${figures.quests} quests finished · ${level.xpToNextLevel} XP to level ${level.level + 1}',
                style: text.bodyMedium?.copyWith(color: colors.xp.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Panel(
          title: 'Screen time earned',
          tint: colors.screenTime,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatMinutes(figures.earnedThisWeek),
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: colors.screenTime.ink),
              ),
              Text(
                'this week, of ${formatMinutes(figures.weeklyCapMinutes)} allowed',
                style: text.bodyMedium?.copyWith(color: colors.screenTime.ink),
              ),
              const SizedBox(height: 10),
              _CapBar(
                earned: figures.earnedThisWeek,
                cap: figures.weeklyCapMinutes,
                colour: colors.screenTime.ink,
              ),
              const SizedBox(height: 10),
              Text(
                'Today: ${formatMinutes(figures.earnedToday)} of ${formatMinutes(figures.dailyCapMinutes)}',
                style: text.bodyMedium?.copyWith(color: colors.screenTime.ink),
              ),
              const SizedBox(height: 6),
              _CapBar(
                earned: figures.earnedToday,
                cap: figures.dailyCapMinutes,
                colour: colors.screenTime.ink,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Counted in your household’s own day, up to and including today.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A figure on its own tinted card, with room for a bar underneath.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.tint, required this.child});

  final String title;
  final Tint tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: tint.fill,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tint.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    );
  }
}

class _CapBar extends StatelessWidget {
  const _CapBar({required this.earned, required this.cap, required this.colour});

  final int earned;
  final int cap;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final full = cap <= 0 ? 0.0 : (earned / cap).clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: full,
        minHeight: 10,
        color: colour,
        backgroundColor: Colors.white,
      ),
    );
  }
}
