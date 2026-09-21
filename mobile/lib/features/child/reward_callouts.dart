import 'package:flutter/material.dart';

import '../../core/models/child_progress.dart';
import '../../core/models/chore.dart';
import '../../shared/badges.dart';
import '../../shared/difficulty_xp.dart';
import '../../shared/leveling.dart';
import '../../shared/story_chapters.dart';

/// What an approved quest just earned: its XP, a new level, and any badge or
/// story chapter it unlocked.
///
/// Read from the child's progress before the photo was sent and after it was
/// approved, both of which the app already fetches, so no new request or
/// polling is involved. With nothing known from before, only the XP shows:
/// it is fixed by the quest's difficulty, so it needs no comparison.
class RewardCallouts extends StatelessWidget {
  const RewardCallouts({
    super.key,
    required this.difficulty,
    required this.before,
    required this.after,
  });

  final QuestDifficulty difficulty;
  final ChildProgress? before;
  final ChildProgress? after;

  @override
  Widget build(BuildContext context) {
    final before = this.before;
    final after = this.after;
    final gained = xpFor(difficulty);

    final newLevel = before != null &&
            after != null &&
            levelFor(after.xp).level > levelFor(before.xp).level
        ? levelFor(after.xp).level
        : null;

    final newBadges = before == null || after == null
        ? const <BadgeStatus>[]
        : [
            for (final badge in after.badges)
              if (badge.earned &&
                  !before.badges.any((b) => b.key == badge.key && b.earned))
                badge,
          ];

    final newChapters = after == null
        ? const <StoryChapter>[]
        : newlyUnlockedChapters(before, after);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Callout(
          leading: const Icon(Icons.star_rounded, size: 34, color: Color(0xFFE0A100)),
          title: '+$gained XP',
          subtitle: newLevel == null ? 'XP earned' : 'Level up! You are level $newLevel.',
          background: const Color(0xFFFFF1C2),
          ink: const Color(0xFF6E5200),
        ),
        for (final badge in newBadges)
          _Callout(
            leading: Icon(
              badgeStyleFor(badge.key).icon,
              size: 34,
              color: badgeStyleFor(badge.key).ink,
            ),
            title: 'New badge: ${badgeStyleFor(badge.key).title}',
            subtitle: badgeStyleFor(badge.key).goal(badge.target),
            background: badgeStyleFor(badge.key).background,
            ink: badgeStyleFor(badge.key).ink,
          ),
        for (final chapter in newChapters)
          _Callout(
            leading: ExcludeSemantics(
              child: Text(chapter.emoji, style: const TextStyle(fontSize: 30)),
            ),
            title: 'Story chapter unlocked!',
            subtitle: 'Chapter ${chapter.number}: ${chapter.title}',
            background: chapter.background,
            ink: chapter.ink,
          ),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.ink,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Color background;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        color: background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(width: 44, child: Center(child: leading)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    Text(subtitle, style: text.bodyMedium?.copyWith(color: ink)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
