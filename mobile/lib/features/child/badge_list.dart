import 'package:flutter/material.dart';

import '../../core/models/child_progress.dart';
import '../../shared/badges.dart';

/// Every badge, earned ones and the rest, a few at a time.
///
/// A long grid buries what a child has actually earned, so only the first
/// [shownAtFirst] are listed until "See more" is tapped. With no more than
/// that, no control appears at all.
class BadgeList extends StatefulWidget {
  const BadgeList({super.key, required this.badges, this.shownAtFirst = 6});

  final List<BadgeStatus> badges;
  final int shownAtFirst;

  @override
  State<BadgeList> createState() => _BadgeListState();
}

class _BadgeListState extends State<BadgeList> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final badges = widget.badges;
    final hidden = badges.length - widget.shownAtFirst;
    final shown = _showAll ? badges : badges.take(widget.shownAtFirst);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final badge in shown) _BadgeRow(badge: badge),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(_showAll
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded),
              label: Text(_showAll ? 'See fewer' : 'See more ($hidden)'),
            ),
          ),
      ],
    );
  }
}

/// One badge: bright with the day it was earned, or pale with how far there
/// is still to go.
class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.badge});

  final BadgeStatus badge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = badgeStyleFor(badge.key);
    final earnedAt = badge.earnedAt;
    final earned = earnedAt != null;
    final fraction = badge.target <= 0 ? 0.0 : badge.progress / badge.target;
    final progressLabel = style.progressLabel(badge.progress, badge.target);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: earned ? style.background : scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: earned ? Colors.white : scheme.surfaceContainerHighest,
              ),
              child: BadgeArt(
                style,
                size: 30,
                colour: earned ? style.ink : scheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    style.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: earned ? style.ink : null,
                    ),
                  ),
                  Text(
                    style.goal(badge.target),
                    style: text.bodyMedium?.copyWith(
                      color: earned ? style.ink : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (earned)
                    Text(
                      'Earned ${MaterialLocalizations.of(context).formatShortMonthDay(earnedAt.toLocal())}',
                      style: text.labelLarge?.copyWith(
                        color: style.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 8,
                        backgroundColor: scheme.surfaceContainerHighest,
                        // A progress bar's spoken value must be a number from
                        // 0 to 100; the words go in the label.
                        semanticsLabel: '${style.title}: $progressLabel',
                        semanticsValue: '${(fraction * 100).round()}',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progressLabel,
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
