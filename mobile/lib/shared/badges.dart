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

const _quests = ('quest', 'quests');

final _styles = <String, BadgeStyle>{
  'first_quest': BadgeStyle(
    title: 'Rookie Hero',
    goal: (target) => 'Finish your very first quest.',
    unit: _quests,
    icon: Icons.flag_rounded,
    background: const Color(0xFFD9F0CB),
    ink: const Color(0xFF2B6320),
  ),
  'streak_7': BadgeStyle(
    title: 'Streak Star',
    goal: (target) => 'Finish a quest $target days in a row.',
    unit: ('day', 'days'),
    icon: Icons.local_fire_department_rounded,
    background: const Color(0xFFFFE3CC),
    ink: const Color(0xFF833F12),
  ),
  'quests_25': BadgeStyle(
    title: 'Chore Champion',
    goal: (target) => 'Finish $target quests.',
    unit: _quests,
    icon: Icons.emoji_events_rounded,
    background: const Color(0xFFFFF1C2),
    ink: const Color(0xFF6E5200),
  ),
  'kitchen_hero': BadgeStyle(
    title: 'Kitchen Hero',
    goal: (target) => 'Finish $target quests in the kitchen.',
    unit: _quests,
    icon: Icons.kitchen_rounded,
    background: const Color(0xFFFFE3CC),
    ink: const Color(0xFF833F12),
  ),
  'bedroom_hero': BadgeStyle(
    title: 'Bedroom Hero',
    goal: (target) => 'Finish $target quests in the bedroom.',
    unit: _quests,
    icon: Icons.bed_rounded,
    background: const Color(0xFFE4E1FF),
    ink: const Color(0xFF3B3585),
  ),
  'study_star': BadgeStyle(
    title: 'Study Star',
    goal: (target) => 'Finish $target quests at the study table.',
    unit: _quests,
    icon: Icons.menu_book_rounded,
    background: const Color(0xFFD5F0EC),
    ink: const Color(0xFF0F5E56),
  ),
  'outdoor_explorer': BadgeStyle(
    title: 'Outdoor Explorer',
    goal: (target) => 'Finish $target quests outdoors.',
    unit: _quests,
    icon: Icons.park_rounded,
    background: const Color(0xFFD9F0CB),
    ink: const Color(0xFF2B6320),
  ),
  'early_bird': BadgeStyle(
    title: 'Early Bird',
    goal: (target) => 'Finish a quest before 9 in the morning.',
    unit: _quests,
    icon: Icons.wb_twilight_rounded,
    background: const Color(0xFFFFF1C2),
    ink: const Color(0xFF6E5200),
  ),
  'weekend_warrior': BadgeStyle(
    title: 'Weekend Warrior',
    goal: (target) => 'Finish a quest on a Saturday and on a Sunday.',
    unit: ('weekend', 'weekends'),
    icon: Icons.weekend_rounded,
    background: const Color(0xFFF7DEE9),
    ink: const Color(0xFF822B52),
  ),
  'perfect_week': BadgeStyle(
    title: 'Perfect Week',
    goal: (target) => 'Finish a quest every day of one week.',
    unit: ('week', 'weeks'),
    icon: Icons.event_available_rounded,
    background: const Color(0xFFD6E7F5),
    ink: const Color(0xFF1D4A73),
  ),
  'helping_hand': BadgeStyle(
    title: 'Helping Hand',
    goal: (target) => 'Finish $target quests in one day.',
    unit: _quests,
    icon: Icons.volunteer_activism_rounded,
    background: const Color(0xFFFFE9B8),
    ink: const Color(0xFF6E4A00),
  ),
  'century_club': BadgeStyle(
    title: 'Century Club',
    goal: (target) => 'Finish $target quests.',
    unit: _quests,
    icon: Icons.military_tech_rounded,
    background: const Color(0xFFE4E1FF),
    ink: const Color(0xFF3B3585),
  ),
  'team_player': BadgeStyle(
    title: 'Team Player',
    goal: (target) => 'Help your family finish a family quest.',
    unit: ('quest', 'quests'),
    icon: Icons.groups_rounded,
    background: const Color(0xFFD5F0EC),
    ink: const Color(0xFF0F5E56),
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

/// Every badge the app can draw, in the order the server sends them.
Iterable<String> get knownBadgeKeys => _styles.keys;
