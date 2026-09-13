import 'api_dates.dart';

/// The kinds of row the ledger holds.
enum LedgerKind {
  earned,
  consumed,
  reversal;

  /// Null for a kind this version of the app does not know, which the report
  /// leaves out rather than guess at.
  static LedgerKind? parse(String? raw) => switch (raw) {
        'earned' => earned,
        'consumed' => consumed,
        'reversal' => reversal,
        _ => null,
      };
}

/// One row of a child's screen-time ledger.
class LedgerLine {
  const LedgerLine({
    required this.id,
    required this.kind,
    required this.minutes,
    required this.points,
    required this.minutesGross,
    required this.minutesForfeited,
    required this.forDate,
    required this.note,
    required this.chore,
    required this.at,
  });

  final int id;
  final LedgerKind kind;

  /// Signed: positive adds screen time, negative takes it away.
  final int minutes;

  /// For an earning: the chore's points, what they were worth before the
  /// limits, and how much the limits trimmed.
  final int? points;
  final int? minutesGross;
  final int? minutesForfeited;

  /// The day it counts towards, which for an earning is the day the photo was
  /// sent.
  final DateTime forDate;
  final String? note;

  /// The chore behind an earning or a reversal. Null for screen time used.
  final String? chore;
  final DateTime at;
}

class ReportTotals {
  const ReportTotals({
    required this.earned,
    required this.consumed,
    required this.reversed,
    required this.forfeited,
  });

  factory ReportTotals.fromJson(Map<String, dynamic> json) => ReportTotals(
        earned: json['earned'] as int,
        consumed: json['consumed'] as int,
        reversed: json['reversed'] as int,
        forfeited: json['forfeited'] as int,
      );

  /// Every total is a positive number of minutes.
  final int earned;
  final int consumed;
  final int reversed;

  /// Minutes chores would have earned beyond the daily or weekly limit.
  final int forfeited;
}

/// A parent's report on one child: the balance, the limits, and the ledger
/// behind them, as the server computed them.
class ScreenTimeReport {
  const ScreenTimeReport({
    required this.childId,
    required this.childName,
    required this.today,
    required this.balanceMinutes,
    required this.earnedToday,
    required this.earnedThisWeek,
    required this.dailyCapMinutes,
    required this.weeklyCapMinutes,
    required this.totals,
    required this.entries,
  });

  factory ScreenTimeReport.fromJson(Map<String, dynamic> json) {
    final child = json['child'] as Map<String, dynamic>;
    return ScreenTimeReport(
      childId: child['id'] as int,
      childName: child['name'] as String,
      today: parseApiDate(json['today'] as String),
      balanceMinutes: json['balance_minutes'] as int,
      earnedToday: json['earned_today'] as int,
      earnedThisWeek: json['earned_this_week'] as int,
      dailyCapMinutes: json['daily_cap_minutes'] as int,
      weeklyCapMinutes: json['weekly_cap_minutes'] as int,
      totals: ReportTotals.fromJson(json['totals'] as Map<String, dynamic>),
      entries: [
        for (final raw in (json['entries'] as List? ?? const [])
            .cast<Map<String, dynamic>>())
          if (LedgerKind.parse(raw['type'] as String?) case final kind?)
            LedgerLine(
              id: raw['id'] as int,
              kind: kind,
              minutes: raw['minutes'] as int,
              points: (raw['points'] as num?)?.toInt(),
              minutesGross: (raw['minutes_gross'] as num?)?.toInt(),
              minutesForfeited: (raw['minutes_forfeited'] as num?)?.toInt(),
              forDate: parseApiDate(raw['for_date'] as String),
              note: raw['note'] as String?,
              chore: raw['chore'] as String?,
              at: DateTime.parse(raw['at'] as String),
            ),
      ],
    );
  }

  final int childId;
  final String childName;

  /// The server's date. Days and limits are counted in it, and the phone's own
  /// date can differ, so the chart is drawn from this one.
  final DateTime today;

  /// Can be below zero after an overturned approval whose minutes were spent.
  final int balanceMinutes;
  final int earnedToday;
  final int earnedThisWeek;
  final int dailyCapMinutes;
  final int weeklyCapMinutes;
  final ReportTotals totals;

  /// The latest rows first. The server sends at most 200.
  final List<LedgerLine> entries;

  /// Minutes earned on each of the [days] days up to and including [today],
  /// oldest first.
  ///
  /// Earnings only, the same figure the daily limit is measured against, so a
  /// day's bar can be read against that limit. Minutes taken back are listed
  /// in the history, not subtracted here. Built from [entries], so a child
  /// with more than 200 recent rows shows only the days those rows reach.
  List<(DateTime, int)> earnedByDay({int days = 7}) {
    final end = DateTime(today.year, today.month, today.day);
    final byDay = <DateTime, int>{};
    for (final line in entries) {
      if (line.kind != LedgerKind.earned) continue;
      final day = DateTime(line.forDate.year, line.forDate.month, line.forDate.day);
      byDay[day] = (byDay[day] ?? 0) + line.minutes;
    }
    return [
      for (var offset = days - 1; offset >= 0; offset--)
        () {
          final day = DateTime(end.year, end.month, end.day - offset);
          return (day, byDay[day] ?? 0);
        }(),
    ];
  }
}
