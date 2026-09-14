import 'package:flutter/material.dart';

/// How a badge looks and reads.
///
/// The server stores only the key and alone decides when a badge is earned,
/// sending each one's target with it. The words and artwork live here, so
/// they can change without touching the rules, and no rule's number is
/// repeated in the app.
class BadgeStyle {
  const BadgeStyle({
    required this.title,
    required this.goal,
    required this.unit,
    required this.icon,
    required this.background,
    required this.ink,
  });

  final String title;

  /// How to earn it, worded around the target the server sends.
  final String Function(int target) goal;

  /// What progress is counted in: singular, then plural.
  final (String, String) unit;

  final IconData icon;
  final Color background;
  final Color ink;

  String progressLabel(int progress, int target) =>
      '$progress of $target ${target == 1 ? unit.$1 : unit.$2}';
}

final _styles = <String, BadgeStyle>{
  'first_quest': BadgeStyle(
    title: 'First quest',
    goal: (target) => 'Finish your very first quest.',
    unit: ('quest', 'quests'),
    icon: Icons.flag_rounded,
    background: const Color(0xFFD9F0CB),
    ink: const Color(0xFF2B6320),
  ),
  'streak_7': BadgeStyle(
    title: 'On fire',
    goal: (target) => 'Finish a quest $target days in a row.',
    unit: ('day', 'days'),
    icon: Icons.local_fire_department_rounded,
    background: const Color(0xFFFFE3CC),
    ink: const Color(0xFF833F12),
  ),
  'quests_25': BadgeStyle(
    title: 'Quest hero',
    goal: (target) => 'Finish $target quests.',
    unit: ('quest', 'quests'),
    icon: Icons.emoji_events_rounded,
    background: const Color(0xFFFFF1C2),
    ink: const Color(0xFF6E5200),
  ),
};

/// A badge this version of the app does not know yet still shows, plainly.
BadgeStyle badgeStyleFor(String key) =>
    _styles[key] ??
    BadgeStyle(
      title: 'Badge',
      goal: (target) => '',
      unit: ('', ''),
      icon: Icons.military_tech_rounded,
      background: const Color(0xFFE2EFE7),
      ink: const Color(0xFF12503A),
    );
