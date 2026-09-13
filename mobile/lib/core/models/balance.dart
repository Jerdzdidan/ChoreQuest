/// A child's screen time as the server computes it: what they have to spend,
/// and how much room is left under today's and this week's limits.
class Balance {
  const Balance({
    required this.balanceMinutes,
    required this.earnedToday,
    required this.earnedThisWeek,
    required this.dailyCapMinutes,
    required this.weeklyCapMinutes,
    required this.dailyRemaining,
    required this.weeklyRemaining,
    required this.minutesPerPoint,
  });

  factory Balance.fromJson(Map<String, dynamic> json) => Balance(
        balanceMinutes: json['balance_minutes'] as int,
        earnedToday: json['earned_today'] as int,
        earnedThisWeek: json['earned_this_week'] as int,
        dailyCapMinutes: json['daily_cap_minutes'] as int,
        weeklyCapMinutes: json['weekly_cap_minutes'] as int,
        dailyRemaining: json['daily_remaining'] as int,
        weeklyRemaining: json['weekly_remaining'] as int,
        minutesPerPoint: json['minutes_per_point'] as int,
      );

  /// Can briefly be below zero after a parent overturns an approval whose
  /// minutes were already spent. The screen shows zero in that case.
  final int balanceMinutes;
  final int earnedToday;
  final int earnedThisWeek;
  final int dailyCapMinutes;
  final int weeklyCapMinutes;
  final int dailyRemaining;
  final int weeklyRemaining;
  final int minutesPerPoint;

  int get spendableMinutes => balanceMinutes < 0 ? 0 : balanceMinutes;

  /// Nothing more can be earned today, by the daily or the weekly limit.
  bool get earningBlocked => dailyRemaining == 0 || weeklyRemaining == 0;
}

class ConsumeResult {
  const ConsumeResult({
    required this.requestedMinutes,
    required this.consumedMinutes,
    required this.balanceMinutes,
  });

  factory ConsumeResult.fromJson(Map<String, dynamic> json) => ConsumeResult(
        requestedMinutes: json['requested_minutes'] as int,
        consumedMinutes: json['consumed_minutes'] as int,
        balanceMinutes: json['balance_minutes'] as int,
      );

  final int requestedMinutes;

  /// Never more than was available. The server clamps it, so a tampered app
  /// cannot spend minutes that were never earned.
  final int consumedMinutes;
  final int balanceMinutes;
}
