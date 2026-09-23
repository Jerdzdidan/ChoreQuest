import 'api_dates.dart';

/// One child's figures for the parent's Activity tab (ACT1), as the server
/// assembled them: how much of what was given got done, the streak, the level
/// and the week's minutes.
///
/// Every figure comes from the same records the rest of the app reads, in one
/// answer, so switching children changes all of them together.
class ChildActivity {
  const ChildActivity({
    required this.childId,
    required this.childName,
    required this.avatar,
    required this.today,
    required this.xp,
    required this.quests,
    required this.currentStreak,
    required this.bestStreak,
    required this.todayCounted,
    required this.completionDays,
    required this.questsDue,
    required this.questsDone,
    required this.earnedToday,
    required this.earnedThisWeek,
    required this.dailyCapMinutes,
    required this.weeklyCapMinutes,
  });

  factory ChildActivity.fromJson(Map<String, dynamic> json) {
    final child = json['child'] as Map<String, dynamic>;
    final streak = json['streak'] as Map<String, dynamic>? ?? const {};
    final completion = json['completion'] as Map<String, dynamic>? ?? const {};
    return ChildActivity(
      childId: child['id'] as int,
      childName: child['name'] as String,
      avatar: child['avatar'] as String? ?? '',
      today: parseApiDate(json['today'] as String),
      xp: json['xp'] as int? ?? 0,
      quests: json['quests'] as int? ?? 0,
      currentStreak: streak['current'] as int? ?? 0,
      bestStreak: streak['best'] as int? ?? 0,
      todayCounted: streak['today_counted'] as bool? ?? false,
      completionDays: completion['days'] as int? ?? 0,
      questsDue: completion['due'] as int? ?? 0,
      questsDone: completion['done'] as int? ?? 0,
      earnedToday: json['earned_today'] as int? ?? 0,
      earnedThisWeek: json['earned_this_week'] as int? ?? 0,
      dailyCapMinutes: json['daily_cap_minutes'] as int? ?? 0,
      weeklyCapMinutes: json['weekly_cap_minutes'] as int? ?? 0,
    );
  }

  final int childId;
  final String childName;
  final String avatar;

  /// The household's date, which the days and the week are counted in.
  final DateTime today;
  final int xp;

  /// Approved quests, ever.
  final int quests;
  final int currentStreak;
  final int bestStreak;
  final bool todayCounted;

  /// How many days the completion figures cover, up to and including today.
  final int completionDays;

  /// Quests given over those days, and how many were done.
  final int questsDue;
  final int questsDone;

  final int earnedToday;
  final int earnedThisWeek;
  final int dailyCapMinutes;
  final int weeklyCapMinutes;

  /// Done out of given, from 0 to 1, or null when nothing was given: a child
  /// with no chores has no rate, rather than a rate of nought.
  double? get completion => questsDue == 0 ? null : questsDone / questsDue;
}
