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

/// The registry key for taking a hat or a pet off (headwear.dart, pets.dart):
/// a choice every child has, not a reward.
const _nothing = 'none';

/// Every level-gated reward, merged from the registries and grouped by the
/// level that unlocks it, lowest first: outfits, headwear, pets and room
/// items (cosmetics.dart) and the animals that need a level (avatars.dart).
/// Level 1 holds what every child starts with.
///
/// Pure: it reads only the registries, so it needs no table and no request,
/// and a new registry entry appears on the track by itself. Levels with
/// nothing to unlock are left out, and so are "No hat" and "No pet".
List<TrackLevel> rewardTrack() {
  final byLevel = <int, List<TrackReward>>{};

  for (final category in CosmeticCategory.values) {
    for (final MapEntry(:key, value: style) in cosmeticsIn(category).entries) {
      if (key == _nothing) continue;
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
    this.asset,
    this.tinted = false,
  });

  final String title;
  final String kind;
  final String howToEarn;
  final bool earned;
  final IconData? icon;
  final String? emoji;
  final Color background;
  final Color ink;

  /// The drawing under assets/, when there is one.
  final String? asset;

  /// Whether that drawing is black on transparent and takes [ink], as the
  /// badges do, rather than a picture in its own colours.
  final bool tinted;
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
        asset: badgeStyleFor(badge.key).asset,
        tinted: true,
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
        asset: chapter.asset,
      ),
  ];
  final all = [...badges, ...chapters];
  return [
    ...all.where((reward) => reward.earned),
    ...all.where((reward) => !reward.earned),
  ];
}

/// Something the child has earned, and when: one line of the "recently
/// earned" strip (RW2).
class RecentReward {
  const RecentReward({
    required this.title,
    required this.kind,
    required this.at,
    required this.background,
    this.ink,
    this.icon,
    this.emoji,
    this.asset,
    this.tinted = false,
  });

  final String title;
  final String kind;
  final DateTime at;
  final Color background;
  final Color? ink;
  final IconData? icon;
  final String? emoji;
  final String? asset;

  /// Whether the drawing is black on transparent and takes [ink].
  final bool tinted;
}

/// The last few things the child earned, newest first: badges, the story
/// chapters those badges opened, and cosmetics their level unlocked.
///
/// Read from what the server already records (when each badge was earned,
/// when each cosmetic was unlocked) rather than from a feed of its own, so
/// it can never disagree with them. Two things are left out because nothing
/// dates them: chapters opened by a count of quests rather than a badge, and
/// animals, which follow the level without being recorded. Starter items are
/// left out too; every child has those from the first day. A brand-new child
/// therefore gets an empty list.
///
/// Things earned in the same moment, such as a badge and the chapter it
/// opened, or everything one level unlocked, keep the order they are
/// gathered in: badges, then chapters, then cosmetics in registry order.
List<RecentReward> recentlyEarned(ChildProgress progress, Wardrobe? wardrobe, {int limit = 3}) {
  final earnedAt = <String, DateTime>{
    for (final badge in progress.badges) badge.key: ?badge.earnedAt,
  };

  final earned = <RecentReward>[
    for (final badge in progress.badges)
      if (earnedAt[badge.key] case final at?)
        RecentReward(
          title: badgeStyleFor(badge.key).title,
          kind: 'Badge',
          at: at,
          icon: badgeStyleFor(badge.key).icon,
          background: badgeStyleFor(badge.key).background,
          ink: badgeStyleFor(badge.key).ink,
          asset: badgeStyleFor(badge.key).asset,
          tinted: true,
        ),
    for (final chapter in storyChapters)
      if (chapter.milestone case BadgeMilestone(:final badgeKey))
        if (earnedAt[badgeKey] case final at?)
          RecentReward(
            title: 'Chapter ${chapter.number}: ${chapter.title}',
            kind: 'Story',
            at: at,
            emoji: chapter.emoji,
            asset: chapter.asset,
            background: chapter.background,
            ink: chapter.ink,
          ),
    for (final category in CosmeticCategory.values)
      for (final MapEntry(:key, value: style) in cosmeticsIn(category).entries)
        if (style.unlockLevel > 1)
          if (_unlockedAt(wardrobe, category, key) case final at?)
            RecentReward(
              title: style.title,
              kind: kindOf(category),
              at: at,
              emoji: style.emoji,
              asset: style.asset,
              background: style.background,
            ),
  ];

  final newestFirst = [...earned.indexed]..sort((a, b) {
      final byTime = b.$2.at.compareTo(a.$2.at);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, reward) in newestFirst.take(limit)) reward];
}

DateTime? _unlockedAt(Wardrobe? wardrobe, CosmeticCategory category, String key) {
  for (final item in wardrobe?.items ?? const <OwnedCosmetic>[]) {
    if (item.category == category && item.key == key) return item.unlockedAt;
  }
  return null;
}
