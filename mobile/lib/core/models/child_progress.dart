import 'api_dates.dart';

/// A child's game progress, as the server derives it from approved photos.
///
/// Read-only and separate from screen time: the ledger alone decides minutes.
class ChildProgress {
  const ChildProgress({required this.today, required this.xp});

  factory ChildProgress.fromJson(Map<String, dynamic> json) => ChildProgress(
        today: parseApiDate(json['today'] as String),
        xp: json['xp'] as int,
      );

  /// The server's date, which submissions count against.
  final DateTime today;

  /// One for every approved photo. Goes down again if a grown-up changes an
  /// approval to not done.
  final int xp;
}
