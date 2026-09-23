import 'package:flutter/material.dart';

/// A badge's picture: the drawn icon from game-icons.net (L1) in the colour
/// asked for, or the Material icon when a badge has no drawing yet.
class BadgeArt extends StatelessWidget {
  const BadgeArt(this.style, {super.key, this.size = 30, this.colour});

  final BadgeStyle style;
  final double size;

  /// Defaults to the badge's own ink; pass the pale colour for one not earned.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final asset = style.asset;
    final ink = colour ?? style.ink;
    if (asset == null) return Icon(style.icon, size: size, color: ink);

    return Image.asset(
      asset,
      width: size,
      height: size,
      // The drawings are black on transparent, so they take the colour of
      // whatever they are shown on.
      color: ink,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

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
    this.asset,
  });

  final String title;

  /// How to earn it, worded around the target the server sends.
  final String Function(int target) goal;

  /// What progress is counted in: singular, then plural.
  final (String, String) unit;

  /// The drawn badge under assets/badges/, from game-icons.net (L1). Black
  /// on transparent, so it is tinted with [ink] where it is shown; the Material
  /// [icon] stands in if it is missing.
  final String? asset;

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
    asset: 'assets/badges/first_quest.png',
    goal: (target) => 'Finish your very first quest.',
    unit: _quests,
    icon: Icons.flag_rounded,
    background: const Color(0xFFD9F0CB),
    ink: const Color(0xFF2B6320),
  ),
  'streak_7': BadgeStyle(
    title: 'Streak Star',
    asset: 'assets/badges/streak_7.png',
    goal: (target) => 'Finish a quest $target days in a row.',
    unit: ('day', 'days'),
    icon: Icons.local_fire_department_rounded,
    background: const Color(0xFFFFE3CC),
    ink: const Color(0xFF833F12),
  ),
  'quests_25': BadgeStyle(
    title: 'Chore Champion',
    asset: 'assets/badges/quests_25.png',
    goal: (target) => 'Finish $target quests.',
    unit: _quests,
    icon: Icons.emoji_events_rounded,
    background: const Color(0xFFFFF1C2),
    ink: const Color(0xFF6E5200),
  ),
  'kitchen_hero': BadgeStyle(
    title: 'Kitchen Hero',
    asset: 'assets/badges/kitchen_hero.png',
    goal: (target) => 'Finish $target quests in the kitchen.',
    unit: _quests,
    icon: Icons.kitchen_rounded,
    background: const Color(0xFFFFE3CC),
    ink: const Color(0xFF833F12),
  ),
  'bedroom_hero': BadgeStyle(
    title: 'Bedroom Hero',
    asset: 'assets/badges/bedroom_hero.png',
    goal: (target) => 'Finish $target quests in the bedroom.',
    unit: _quests,
    icon: Icons.bed_rounded,
    background: const Color(0xFFE4E1FF),
    ink: const Color(0xFF3B3585),
  ),
  'study_star': BadgeStyle(
    title: 'Study Star',
    asset: 'assets/badges/study_star.png',
    goal: (target) => 'Finish $target quests at the study table.',
    unit: _quests,
    icon: Icons.menu_book_rounded,
    background: const Color(0xFFD5F0EC),
    ink: const Color(0xFF0F5E56),
  ),
  'outdoor_explorer': BadgeStyle(
    title: 'Outdoor Explorer',
    asset: 'assets/badges/outdoor_explorer.png',
    goal: (target) => 'Finish $target quests outdoors.',
    unit: _quests,
    icon: Icons.park_rounded,
    background: const Color(0xFFD9F0CB),
    ink: const Color(0xFF2B6320),
  ),
  'early_bird': BadgeStyle(
    title: 'Early Bird',
    asset: 'assets/badges/early_bird.png',
    goal: (target) => 'Finish a quest before 9 in the morning.',
    unit: _quests,
    icon: Icons.wb_twilight_rounded,
    background: const Color(0xFFFFF1C2),
    ink: const Color(0xFF6E5200),
  ),
  'weekend_warrior': BadgeStyle(
    title: 'Weekend Warrior',
    asset: 'assets/badges/weekend_warrior.png',
    goal: (target) => 'Finish a quest on a Saturday and on a Sunday.',
    unit: ('weekend', 'weekends'),
    icon: Icons.weekend_rounded,
    background: const Color(0xFFF7DEE9),
    ink: const Color(0xFF822B52),
  ),
  'perfect_week': BadgeStyle(
    title: 'Perfect Week',
    asset: 'assets/badges/perfect_week.png',
    goal: (target) => 'Finish a quest every day of one week.',
    unit: ('week', 'weeks'),
    icon: Icons.event_available_rounded,
    background: const Color(0xFFD6E7F5),
    ink: const Color(0xFF1D4A73),
  ),
  'helping_hand': BadgeStyle(
    title: 'Helping Hand',
    asset: 'assets/badges/helping_hand.png',
    goal: (target) => 'Finish $target quests in one day.',
    unit: _quests,
    icon: Icons.volunteer_activism_rounded,
    background: const Color(0xFFFFE9B8),
    ink: const Color(0xFF6E4A00),
  ),
  'century_club': BadgeStyle(
    title: 'Century Club',
    asset: 'assets/badges/century_club.png',
    goal: (target) => 'Finish $target quests.',
    unit: _quests,
    icon: Icons.military_tech_rounded,
    background: const Color(0xFFE4E1FF),
    ink: const Color(0xFF3B3585),
  ),
  'team_player': BadgeStyle(
    title: 'Team Player',
    asset: 'assets/badges/team_player.png',
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
