import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A bar for each day, the last day darkest, with each day's figure above it
/// and its weekday below.
///
/// Read aloud as a list of days, since the bars themselves mean nothing to a
/// screen reader; [describe] words each day's figure for that.
class DayBars extends StatelessWidget {
  const DayBars({
    super.key,
    required this.days,
    required this.describe,
    this.height = 180,
  });

  final List<(DateTime, int)> days;
  final String Function(int value) describe;
  final double height;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final top = days.fold(1, (most, day) => math.max(most, day.$2));

    return Semantics(
      label: [
        for (final (day, value) in days)
          '${localizations.formatShortMonthDay(day)}: ${describe(value)}',
      ].join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, (day, value)) in days.indexed)
                Expanded(
                  child: Column(
                    children: [
                      Text(value == 0 ? '' : '$value', style: text.labelSmall),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            widthFactor: 0.6,
                            heightFactor: value / top,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: index == days.length - 1
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.5),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        localizations.narrowWeekdays[day.weekday % 7],
                        style: text.labelMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
