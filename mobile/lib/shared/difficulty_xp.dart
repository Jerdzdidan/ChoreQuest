import 'package:flutter/material.dart';

import '../core/models/chore.dart';

/// How each difficulty tier looks, and the XP an approved quest of that tier
/// earns.
///
/// The XP numbers mirror App\Domain\Progress\Difficulty on the server, which
/// is the copy that counts. This one only shows a quest's reward before it is
/// earned, so the two must be changed together.
class DifficultyStyle {
  const DifficultyStyle({
    required this.xp,
    required this.icon,
    required this.background,
    required this.ink,
  });

  final int xp;
  final IconData icon;
  final Color background;
  final Color ink;
}

const _styles = <QuestDifficulty, DifficultyStyle>{
  QuestDifficulty.easy: DifficultyStyle(
    xp: 5,
    icon: Icons.signal_cellular_alt_1_bar,
    background: Color(0xFFD9F0CB),
    ink: Color(0xFF2B6320),
  ),
  QuestDifficulty.medium: DifficultyStyle(
    xp: 10,
    icon: Icons.signal_cellular_alt_2_bar,
    background: Color(0xFFFFE9B8),
    ink: Color(0xFF6E4A00),
  ),
  QuestDifficulty.hard: DifficultyStyle(
    xp: 20,
    icon: Icons.signal_cellular_alt,
    background: Color(0xFFFFE3CC),
    ink: Color(0xFF833F12),
  ),
};

DifficultyStyle difficultyStyleFor(QuestDifficulty difficulty) =>
    _styles[difficulty]!;

/// XP an approved quest of [difficulty] earns.
int xpFor(QuestDifficulty difficulty) => difficultyStyleFor(difficulty).xp;
