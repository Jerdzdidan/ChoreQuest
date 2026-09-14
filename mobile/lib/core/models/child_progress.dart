import 'api_dates.dart';

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
  });

  factory ChildProgress.fromJson(Map<String, dynamic> json) {
    final streak = json['streak'] as Map<String, dynamic>? ?? const {};
    return ChildProgress(
      today: parseApiDate(json['today'] as String),
      xp: json['xp'] as int,
      currentStreak: streak['current'] as int? ?? 0,
      bestStreak: streak['best'] as int? ?? 0,
      todayCounted: streak['today_counted'] as bool? ?? false,
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
}
