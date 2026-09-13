import 'package:flutter/material.dart';

import '../../core/models/chore.dart';
import '../../shared/chore_icons.dart';
import '../../shared/format.dart';
import 'child_providers.dart';

/// One chore, sized to be found and tapped by a child who may not read yet.
/// The picture and the colour of the status carry the meaning; the words are
/// there for whoever can read them.
class ChoreCard extends StatelessWidget {
  const ChoreCard({
    super.key,
    required this.assignment,
    required this.state,
    required this.minutesPerPoint,
    required this.onTap,
  });

  final Assignment assignment;
  final ChoreState state;
  final int? minutesPerPoint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chore = assignment.chore;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final perPoint = minutesPerPoint;
    final due = assignment.dueTime;

    final (statusLabel, statusIcon, statusColour) = switch (state) {
      ChoreState.toDo => ('Take a photo', Icons.photo_camera_rounded, scheme.primary),
      ChoreState.waiting => (
          'A grown-up will check',
          Icons.hourglass_top_rounded,
          const Color(0xFF9A6412),
        ),
      ChoreState.queued => (
          'Saved, sending soon',
          Icons.cloud_upload_rounded,
          const Color(0xFF1D4A73),
        ),
      ChoreState.done => ('Done!', Icons.check_circle_rounded, const Color(0xFF2E7D32)),
      ChoreState.tryAgain => ('Try another photo', Icons.refresh_rounded, scheme.error),
    };
    // A saved photo is already on its way: a second one for the same chore
    // would only reach a grown-up twice.
    final tappable = state != ChoreState.done && state != ChoreState.queued;

    return MergeSemantics(
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tappable ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Opacity(
                  opacity: state == ChoreState.done ? 0.55 : 1,
                  child: ChoreIcon(icon: chore.icon, category: chore.category, size: 72),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chore.name,
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _Pill(
                            icon: Icons.star_rounded,
                            label: perPoint == null
                                ? pointsLabel(assignment.points)
                                : formatMinutes(assignment.points * perPoint),
                          ),
                          if (due != null)
                            _Pill(
                              icon: Icons.schedule,
                              label: MaterialLocalizations.of(context).formatTimeOfDay(
                                TimeOfDay(hour: due.hour, minute: due.minute),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(statusIcon, size: 22, color: statusColour),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              statusLabel,
                              style: text.titleSmall?.copyWith(
                                color: statusColour,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
