import 'package:flutter/material.dart';

import '../core/models/child_progress.dart';
import '../core/models/cosmetics.dart';
import 'avatars.dart';
import 'badges.dart';
import 'cosmetics.dart';
import 'story_chapters.dart';

/// One reward on the track: what it is and how it looks.
class TrackReward {
  const TrackReward({
    required this.title,
    required this.kind,
    required this.emoji,
    required this.background,
    this.asset,
  });

  final String title;

  /// What sort of thing it is, as a child would say it: "Outfit", "Pet".
  final String kind;

  /// Placeholder picture until the drawn art (L1) arrives in [asset].
  final String? emoji;
  final Color background;
  final String? asset;
}

/// A level on the track, and everything reaching it unlocks.
class TrackLevel {
  const TrackLevel({required this.level, required this.rewards});

  final int level;
  final List<TrackReward> rewards;
}

String kindOf(CosmeticCategory category) => switch (category) {
      CosmeticCategory.outfit => 'Outfit',
      CosmeticCategory.headwear => 'Hat',
      CosmeticCategory.pet => 'Pet',
      CosmeticCategory.rug => 'Rug',
      CosmeticCategory.wall => 'Wall art',
      CosmeticCategory.plant => 'Plant',
    };

/// Every level-gated reward, merged from the registries and grouped by the
/// level that unlocks it, lowest first: outfits, headwear, pets and room
/// items (cosmetics.dart) and the animals that need a level (avatars.dart).
///
/// Pure: it reads only the registries, so it needs no table and no request,
/// and a new registry entry appears on the track by itself. Levels with
/// nothing to unlock are left out.
List<TrackLevel> rewardTrack() {
  final byLevel = <int, List<TrackReward>>{};

  for (final category in CosmeticCategory.values) {
    for (final style in cosmeticsIn(category).values) {
      byLevel.putIfAbsent(style.unlockLevel, () => []).add(
            TrackReward(
              title: style.title,
              kind: kindOf(category),
              emoji: style.emoji,
              background: style.background,
              asset: style.asset,
            ),
          );
    }
  }

  for (final entry in avatars.entries) {
    // Animals open from the start are anyone's; only the earned ones are
    // rewards worth showing on the track.
    if (entry.value.unlockLevel <= 1) continue;
    byLevel.putIfAbsent(entry.value.unlockLevel, () => []).add(
          TrackReward(
            title: avatarName(entry.key),
            kind: 'Animal',
            emoji: entry.value.emoji,
            background: entry.value.background,
          ),
        );
  }

  final levels = byLevel.keys.toList()..sort();
  return [
    for (final level in levels)
      TrackLevel(level: level, rewards: List.unmodifiable(byLevel[level]!)),
  ];
}

/// A reward earned by reaching a milestone rather than a level: a badge or a
/// story chapter.
class MilestoneReward {
  const MilestoneReward({
    required this.title,
    required this.kind,
    required this.howToEarn,
    required this.earned,
    required this.icon,
    required this.emoji,
    required this.background,
    required this.ink,
  });

  final String title;
  final String kind;
  final String howToEarn;
  final bool earned;
  final IconData? icon;
  final String? emoji;
  final Color background;
  final Color ink;
}

/// Badges and story chapters, which open at milestones (a number of quests,
/// a streak, a badge) rather than at a level, so they cannot sit on the level
/// track. Earned ones first, in the order the server and the story give.
List<MilestoneReward> milestoneTrack(ChildProgress progress) {
  final badges = [
    for (final badge in progress.badges)
      MilestoneReward(
        title: badgeStyleFor(badge.key).title,
        kind: 'Badge',
        howToEarn: badgeStyleFor(badge.key).goal(badge.target),
        earned: badge.earned,
        icon: badgeStyleFor(badge.key).icon,
        emoji: null,
        background: badgeStyleFor(badge.key).background,
        ink: badgeStyleFor(badge.key).ink,
      ),
  ];
  final chapters = [
    for (final chapter in storyChapters)
      MilestoneReward(
        title: 'Chapter ${chapter.number}: ${chapter.title}',
        kind: 'Story',
        howToEarn: chapter.milestone.describe,
        earned: chapter.unlockedBy(progress),
        icon: null,
        emoji: chapter.emoji,
        background: chapter.background,
        ink: chapter.ink,
      ),
  ];
  final all = [...badges, ...chapters];
  return [
    ...all.where((reward) => reward.earned),
    ...all.where((reward) => !reward.earned),
  ];
}
