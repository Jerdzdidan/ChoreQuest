/// Levels, worked out from XP.
///
/// This file is the one place level thresholds live. Change [xpToReach] and
/// every level label, progress bar and avatar unlock follows. Plain Dart with
/// no imports, so the same rules can be checked outside the app.
library;

/// XP it takes to go up one level.
const xpPerLevel = 10;

/// The total XP a child needs to reach [level]. Level 1 needs none.
///
/// Must grow with every level. A table or a curve can replace this line
/// later without changing anything that uses it.
int xpToReach(int level) => (level - 1) * xpPerLevel;

/// Where a child stands: their level and how far they are towards the next.
class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.xp,
    required this.levelStartXp,
    required this.nextLevelXp,
  });

  final int level;
  final int xp;

  /// The XP at which [level] began.
  final int levelStartXp;

  /// The XP at which the next level begins.
  final int nextLevelXp;

  int get xpIntoLevel => xp - levelStartXp;
  int get xpForLevel => nextLevelXp - levelStartXp;
  int get xpToNextLevel => nextLevelXp - xp;

  /// How full the bar towards the next level is, from 0 up to, never
  /// reaching, 1.
  double get fraction => xpForLevel <= 0 ? 0 : xpIntoLevel / xpForLevel;
}

LevelProgress levelFor(int xp) {
  final earned = xp < 0 ? 0 : xp;
  var level = 1;
  // The second condition stops a mistyped threshold table that stops growing
  // from looping forever.
  while (xpToReach(level + 1) <= earned &&
      xpToReach(level + 1) > xpToReach(level)) {
    level++;
  }
  return LevelProgress(
    level: level,
    xp: earned,
    levelStartXp: xpToReach(level),
    nextLevelXp: xpToReach(level + 1),
  );
}
