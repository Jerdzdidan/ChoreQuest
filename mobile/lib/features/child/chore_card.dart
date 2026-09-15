import 'package:flutter/material.dart';

import '../../core/models/chore.dart';
import '../../shared/chore_icons.dart';
import '../../shared/format.dart';
import '../../shared/leveling.dart';
import 'child_providers.dart';

/// One quest, as a mission card: its picture and name, what it is worth in
/// XP and screen time, how hard it is, and where it stands today.
///
/// Sized to be found and tapped by a child who may not read yet. The picture,
/// the coloured pills and the status icon carry the meaning; the words are
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

  static const _done = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final chore = assignment.chore;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final perPoint = minutesPerPoint;
    final due = assignment.dueTime;
    final difficulty = chore.difficulty;

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
      ChoreState.done => ('Done!', Icons.check_circle_rounded, _done),
      ChoreState.tryAgain => ('Try another photo', Icons.refresh_rounded, scheme.error),
    };
    // A saved photo is already on its way: a second one for the same chore
    // would only reach a grown-up twice.
    final tappable = state != ChoreState.done && state != ChoreState.queued;
    final done = state == ChoreState.done;

    final (difficultyIcon, difficultyBackground, difficultyInk) = switch (difficulty) {
      QuestDifficulty.easy => (
          Icons.signal_cellular_alt_1_bar,
          const Color(0xFFD9F0CB),
          const Color(0xFF2B6320),
        ),
      QuestDifficulty.medium => (
          Icons.signal_cellular_alt_2_bar,
          const Color(0xFFFFE9B8),
          const Color(0xFF6E4A00),
        ),
      QuestDifficulty.hard => (
          Icons.signal_cellular_alt,
          const Color(0xFFFFE3CC),
          const Color(0xFF833F12),
        ),
    };

    return MergeSemantics(
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: done ? _done : scheme.outlineVariant,
            width: done ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: tappable ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            child: Row(
              children: [
                Opacity(
                  opacity: done ? 0.55 : 1,
                  child: ChoreIcon(icon: chore.icon, category: chore.category, size: 64),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chore.name,
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          const _Pill(
                            icon: Icons.star_rounded,
                            label: '+$xpPerApprovedQuest XP',
                            background: Color(0xFFFFF1C2),
                            ink: Color(0xFF6E5200),
                          ),
                          _Pill(
                            icon: Icons.timer_outlined,
                            label: perPoint == null
                                ? pointsLabel(assignment.points)
                                : '+${formatMinutes(assignment.points * perPoint)}',
                            background: const Color(0xFFDCE6F2),
                            ink: const Color(0xFF1D4A73),
                          ),
                          _Pill(
                            icon: difficultyIcon,
                            label: difficulty.label,
                            background: difficultyBackground,
                            ink: difficultyInk,
                          ),
                          if (due != null)
                            _Pill(
                              icon: Icons.schedule,
                              label: MaterialLocalizations.of(context).formatTimeOfDay(
                                TimeOfDay(hour: due.hour, minute: due.minute),
                              ),
                              background: scheme.surfaceContainerHighest,
                              ink: scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                if (tappable)
                  Icon(Icons.chevron_right_rounded, size: 28, color: scheme.onSurfaceVariant)
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.background,
    required this.ink,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ink),
          const SizedBox(width: 4),
          // A pill cannot wrap to a new line the way the pills around it do,
          // so with very large text on a narrow phone the label shortens
          // instead of spilling out of the card.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
