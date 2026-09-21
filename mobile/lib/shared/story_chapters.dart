import 'package:flutter/material.dart';

import '../core/models/child_progress.dart';
import 'badges.dart';

/// What opens a story chapter: a number of approved quests, or a badge.
sealed class ChapterMilestone {
  const ChapterMilestone();

  bool reachedBy(ChildProgress progress);

  /// How to reach it, in a child's words.
  String get describe;
}

/// Opens once the child has this many approved quests.
final class QuestsMilestone extends ChapterMilestone {
  const QuestsMilestone(this.quests);

  final int quests;

  @override
  bool reachedBy(ChildProgress progress) => progress.quests >= quests;

  @override
  String get describe =>
      quests == 1 ? 'Finish your first quest.' : 'Finish $quests quests.';
}

/// Opens once the child has earned this badge (badges.dart).
final class BadgeMilestone extends ChapterMilestone {
  const BadgeMilestone(this.badgeKey);

  final String badgeKey;

  @override
  bool reachedBy(ChildProgress progress) =>
      progress.badges.any((badge) => badge.key == badgeKey && badge.earned);

  @override
  String get describe => 'Earn the ${badgeStyleFor(badgeKey).title} badge.';
}

/// One chapter of the hero's story, and what opens it.
///
/// Shaped like the cosmetic registries: a picture (an emoji placeholder on a
/// colour until the chapter illustrations, A4, arrive in [asset]), a title,
/// and the milestone that unlocks it. Nothing is stored: a chapter is open
/// whenever the child's progress says its milestone is reached, so it can
/// never disagree with the badges and quests it follows from.
class StoryChapter {
  const StoryChapter({
    required this.number,
    required this.title,
    required this.blurb,
    required this.milestone,
    required this.emoji,
    required this.background,
    required this.ink,
    this.asset,
  });

  final int number;
  final String title;

  /// One line of the story, read once the chapter is open.
  final String blurb;
  final ChapterMilestone milestone;
  final String emoji;
  final Color background;
  final Color ink;

  /// The chapter's illustration under assets/, once drawn.
  final String? asset;

  bool unlockedBy(ChildProgress progress) => milestone.reachedBy(progress);
}

/// The story, in order. Titles are the Phase 3 plan's.
const storyChapters = <StoryChapter>[
  StoryChapter(
    number: 1,
    title: 'The New Hero',
    blurb: 'Every hero starts with a single quest. Yours has begun!',
    milestone: QuestsMilestone(1),
    emoji: '🌅',
    background: Color(0xFFFFF1C2),
    ink: Color(0xFF6E5200),
  ),
  StoryChapter(
    number: 2,
    title: 'The Helpful Hero',
    blurb: 'Ten quests done. The whole house has noticed your help.',
    milestone: QuestsMilestone(10),
    emoji: '🏠',
    background: Color(0xFFD9F0CB),
    ink: Color(0xFF2B6320),
  ),
  StoryChapter(
    number: 3,
    title: 'The Streak Keeper',
    blurb: 'Seven days in a row! A true hero keeps going.',
    milestone: BadgeMilestone('streak_7'),
    emoji: '🔥',
    background: Color(0xFFFFE3CC),
    ink: Color(0xFF833F12),
  ),
  StoryChapter(
    number: 4,
    title: 'The Team Quest',
    blurb: 'Heroes are stronger together. Your family finished a big quest!',
    milestone: BadgeMilestone('team_player'),
    emoji: '🤝',
    background: Color(0xFFD5F0EC),
    ink: Color(0xFF0F5E56),
  ),
  StoryChapter(
    number: 5,
    title: 'The Chore Champion',
    blurb: 'Twenty-five quests! You are a champion of your home.',
    milestone: BadgeMilestone('quests_25'),
    emoji: '🏆',
    background: Color(0xFFE4E1FF),
    ink: Color(0xFF3B3585),
  ),
];

/// The chapters [progress] has opened, in story order.
List<StoryChapter> unlockedChapters(ChildProgress progress) => [
      for (final chapter in storyChapters)
        if (chapter.unlockedBy(progress)) chapter,
    ];

/// Chapters open in [after] that were not in [before]: what one approval
/// just unlocked. Nothing when [before] is unknown, rather than announcing
/// every chapter the child already had.
List<StoryChapter> newlyUnlockedChapters(
  ChildProgress? before,
  ChildProgress after,
) {
  if (before == null) return const [];
  return [
    for (final chapter in storyChapters)
      if (chapter.unlockedBy(after) && !chapter.unlockedBy(before)) chapter,
  ];
}
