/// "20 min", "1 h", "1 h 30 min". Negative values keep their sign.
String formatMinutes(int minutes) {
  final sign = minutes < 0 ? '-' : '';
  final total = minutes.abs();
  if (total < 60) return '$sign$total min';
  final hours = total ~/ 60;
  final rest = total % 60;
  return rest == 0 ? '$sign$hours h' : '$sign$hours h $rest min';
}

/// 0.85 as "85%".
String formatPercent(double value) => '${(value * 100).round()}%';

String pointsLabel(int points) => points == 1 ? '1 point' : '$points points';
