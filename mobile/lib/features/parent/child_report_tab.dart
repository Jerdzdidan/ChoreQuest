import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_profile.dart';
import '../../core/models/screen_time_report.dart';
import '../../shared/async_view.dart';
import '../../shared/day_bars.dart';
import '../../shared/format.dart';
import '../../shared/stat_tile.dart';
import 'parent_providers.dart';

/// A child's screen time for the parent: what is left, how close the limits
/// are, the last week, and every minute earned, used or taken back.
class ChildReportTab extends ConsumerWidget {
  const ChildReportTab({super.key, required this.child});

  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(reportProvider(child.id));

    return RefreshIndicator(
      onRefresh: () => ref.refresh(reportProvider(child.id).future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          AsyncView<ScreenTimeReport>(
            value: report,
            onRetry: () => ref.invalidate(reportProvider(child.id)),
            builder: (context, value) => _Report(report: value),
          ),
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.report});

  final ScreenTimeReport report;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final r = report;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 40,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Screen time left',
                        style: text.labelLarge
                            ?.copyWith(color: scheme.onPrimaryContainer),
                      ),
                      Text(
                        formatMinutes(math.max(0, r.balanceMinutes)),
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      if (r.balanceMinutes < 0)
                        Text(
                          '${formatMinutes(-r.balanceMinutes)} to earn back '
                          'first: screen time already used was taken back.',
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Limits', style: text.titleMedium),
        const SizedBox(height: 8),
        _LimitBar(
          label: 'Earned today',
          earned: r.earnedToday,
          limit: r.dailyCapMinutes,
          resets: 'tomorrow',
        ),
        const SizedBox(height: 12),
        _LimitBar(
          label: 'Earned this week',
          earned: r.earnedThisWeek,
          limit: r.weeklyCapMinutes,
          resets: 'on Monday',
        ),
        const SizedBox(height: 24),
        Text('Earned in the last 7 days', style: text.titleMedium),
        const SizedBox(height: 8),
        DayBars(days: r.earnedByDay(), describe: formatMinutes),
        const SizedBox(height: 24),
        Text('Since the start', style: text.titleMedium),
        const SizedBox(height: 8),
        StatTilePair(
          left: StatTile(
            label: 'Earned',
            value: formatMinutes(r.totals.earned),
          ),
          right: StatTile(
            label: 'Used',
            value: formatMinutes(r.totals.consumed),
          ),
        ),
        const SizedBox(height: 8),
        StatTilePair(
          left: StatTile(
            label: 'Taken back',
            value: formatMinutes(r.totals.reversed),
          ),
          right: StatTile(
            label: 'Over the limits',
            value: formatMinutes(r.totals.forfeited),
          ),
        ),
        const SizedBox(height: 24),
        Text('History', style: text.titleMedium),
        const SizedBox(height: 4),
        if (r.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nothing yet. Approved chores and screen time used will show '
              'here.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final line in r.entries) _LedgerRow(line: line),
      ],
    );
  }
}

class _LimitBar extends StatelessWidget {
  const _LimitBar({
    required this.label,
    required this.earned,
    required this.limit,
    required this.resets,
  });

  final String label;
  final int earned;
  final int limit;

  /// When the limit starts again, as it ends a sentence: "tomorrow".
  final String resets;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final reached = earned >= limit;
    final amount = '${formatMinutes(earned)} of ${formatMinutes(limit)}';
    final fraction = limit <= 0 ? 1.0 : math.min(1.0, earned / limit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(amount, style: text.titleSmall),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 10,
            color: reached ? scheme.tertiary : scheme.primary,
            backgroundColor: scheme.surfaceContainerHighest,
            // A progress bar's spoken value must be a number from 0 to 100;
            // the minutes go in the label instead.
            semanticsLabel: '$label: $amount',
            semanticsValue: '${(fraction * 100).round()}',
          ),
        ),
        if (reached) ...[
          const SizedBox(height: 4),
          Text(
            'Limit reached. Chores earn nothing more until it starts again '
            '$resets.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.line});

  final LedgerLine line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = line;

    final (icon, colour, title) = switch (l.kind) {
      LedgerKind.earned => (
          Icons.add_circle_outline_rounded,
          const Color(0xFF2E7D32),
          l.chore ?? 'A chore',
        ),
      LedgerKind.consumed => (
          Icons.play_circle_outline_rounded,
          scheme.primary,
          'Screen time used',
        ),
      LedgerKind.reversal => (
          Icons.undo_rounded,
          scheme.error,
          'Taken back: ${l.chore ?? 'a chore'}',
        ),
    };
    final overLimit = l.minutesForfeited ?? 0;
    final details = [
      MaterialLocalizations.of(context).formatMediumDate(l.forDate),
      if (l.kind == LedgerKind.earned && overLimit > 0)
        '${formatMinutes(overLimit)} over the limit',
      if (l.kind == LedgerKind.reversal && l.note != null) l.note!,
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colour),
      title: Text(title),
      subtitle: Text(details),
      trailing: Text(
        l.minutes > 0 ? '+${formatMinutes(l.minutes)}' : formatMinutes(l.minutes),
        style: text.titleSmall?.copyWith(
          color: colour,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
