/// A child's screen-time rules: the exchange rate, both limits, and the two
/// confidence thresholds that decide what the photo checker may settle alone.
class AllocationRule {
  const AllocationRule({
    required this.childId,
    required this.minutesPerPoint,
    required this.dailyCapMinutes,
    required this.weeklyCapMinutes,
    required this.confidenceHigh,
    required this.confidenceLow,
  });

  factory AllocationRule.fromJson(Map<String, dynamic> json) => AllocationRule(
        childId: json['child_id'] as int,
        minutesPerPoint: json['minutes_per_point'] as int,
        dailyCapMinutes: json['daily_cap_minutes'] as int,
        weeklyCapMinutes: json['weekly_cap_minutes'] as int,
        confidenceHigh: (json['confidence_high'] as num).toDouble(),
        confidenceLow: (json['confidence_low'] as num).toDouble(),
      );

  final int childId;
  final int minutesPerPoint;
  final int dailyCapMinutes;
  final int weeklyCapMinutes;

  /// At or above this, a photo the checker believes is done is approved alone.
  final double confidenceHigh;

  /// At or below this, the photo is sent back to the child to try again.
  final double confidenceLow;

  Map<String, dynamic> toJson() => {
        'minutes_per_point': minutesPerPoint,
        'daily_cap_minutes': dailyCapMinutes,
        'weekly_cap_minutes': weeklyCapMinutes,
        'confidence_high': confidenceHigh,
        'confidence_low': confidenceLow,
      };

  AllocationRule copyWith({
    int? minutesPerPoint,
    int? dailyCapMinutes,
    int? weeklyCapMinutes,
    double? confidenceHigh,
    double? confidenceLow,
  }) =>
      AllocationRule(
        childId: childId,
        minutesPerPoint: minutesPerPoint ?? this.minutesPerPoint,
        dailyCapMinutes: dailyCapMinutes ?? this.dailyCapMinutes,
        weeklyCapMinutes: weeklyCapMinutes ?? this.weeklyCapMinutes,
        confidenceHigh: confidenceHigh ?? this.confidenceHigh,
        confidenceLow: confidenceLow ?? this.confidenceLow,
      );

  /// The two checks the server enforces, mirrored so the form can explain a
  /// problem before anything is sent. The server still decides.
  String? get problem {
    if (confidenceLow >= confidenceHigh) {
      return 'The lower threshold must sit below the upper one, so that '
          'uncertain photos still reach you.';
    }
    if (weeklyCapMinutes < dailyCapMinutes) {
      return 'The weekly limit cannot be lower than the daily limit.';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AllocationRule &&
      other.childId == childId &&
      other.minutesPerPoint == minutesPerPoint &&
      other.dailyCapMinutes == dailyCapMinutes &&
      other.weeklyCapMinutes == weeklyCapMinutes &&
      other.confidenceHigh == confidenceHigh &&
      other.confidenceLow == confidenceLow;

  @override
  int get hashCode => Object.hash(
        childId,
        minutesPerPoint,
        dailyCapMinutes,
        weeklyCapMinutes,
        confidenceHigh,
        confidenceLow,
      );
}
