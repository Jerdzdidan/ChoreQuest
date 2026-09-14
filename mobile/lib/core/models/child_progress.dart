import 'api_dates.dart';

/// One badge in the set, earned or not.
class BadgeStatus {
  const BadgeStatus({
    required this.key,
    required this.earnedAt,
    required this.progress,
    required this.target,
  });

  factory BadgeStatus.fromJson(Map<String, dynamic> json) {
    final earnedAt = json['earned_at'] as String?;
    return BadgeStatus(
      key: json['key'] as String,
      earnedAt: earnedAt == null ? null : DateTime.parse(earnedAt),
      progress: json['progress'] as int,
      target: json['target'] as int,
    );
  }

  /// Which badge, such as `first_quest`. The app draws it from the key.
  final String key;

  /// Null until earned. Once earned, a badge is kept.
  final DateTime? earnedAt;

  /// How far the child is towards [target], never more than it. The target
  /// comes from the server, which alone decides when a badge is earned.
  final int progress;
  final int target;

  bool get earned => earnedAt != null;
}

/// A child's game progress, as the server derives it from approved photos.
///
/// Read-only and separate from screen time: the ledger alone decides minutes.
class ChildProgress {
  const ChildProgress({
    required this.today,
    required this.xp,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.todayCounted = false,
    this.badges = const [],
    this.history = const [],
  });

  factory ChildProgress.fromJson(Map<String, dynamic> json) {
    final streak = json['streak'] as Map<String, dynamic>? ?? const {};
    return ChildProgress(
      today: parseApiDate(json['today'] as String),
      xp: json['xp'] as int,
      currentStreak: streak['current'] as int? ?? 0,
      bestStreak: streak['best'] as int? ?? 0,
      todayCounted: streak['today_counted'] as bool? ?? false,
      badges: [
        for (final raw in (json['badges'] as List? ?? const [])
            .cast<Map<String, dynamic>>())
          BadgeStatus.fromJson(raw),
      ],
      history: [
        for (final raw in (json['history'] as List? ?? const [])
            .cast<Map<String, dynamic>>())
          (parseApiDate(raw['date'] as String), raw['xp'] as int),
      ],
    );
  }

  /// The server's date, which submissions and streaks count in.
  final DateTime today;

  /// One for every approved photo. Goes down again if a grown-up changes an
  /// approval to not done.
  final int xp;

  /// Days in a row with at least one approved quest, up to today. A streak
  /// that reached yesterday still counts while today is not over.
  final int currentStreak;

  /// The longest run of days ever.
  final int bestStreak;

  /// Whether today already has an approved quest. False with a streak above
  /// zero means the streak is waiting for today's quest.
  final bool todayCounted;

  /// Every badge in the set, in the order to show them.
  final List<BadgeStatus> badges;

  /// XP earned on each of the last two weeks' days, oldest first, ending on
  /// [today].
  final List<(DateTime, int)> history;
}
