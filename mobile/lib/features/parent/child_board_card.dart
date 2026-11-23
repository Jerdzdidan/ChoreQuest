import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/child_activity.dart';
import '../../core/models/child_profile.dart';
import '../../core/schedule/next_alarm.dart';
import '../../shared/avatars.dart';
import '../../shared/format.dart';
import '../../shared/inline_error.dart';
import '../../shared/schedule_text.dart';
import '../../shared/theme.dart';
import 'child_detail_screen.dart';
import 'parent_providers.dart';

/// One child on the Board (BD1): their picture and name, what they have
/// earned today against their daily cap and this week against their weekly
/// one, and a way to change either cap for this child alone.
///
/// The figures are the ones the child's own wallet shows, read from the same
/// ledger; nothing here is a household total.
class ChildBoardCard extends ConsumerWidget {
  const ChildBoardCard({super.key, required this.child});

  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityProvider(child.id));
    final figures = activity.value;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ChildDetailScreen(childId: child.id)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  AvatarBadge(child.avatar, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(child.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          child.isLocked
                              ? 'Age ${child.age} · Locked out. Set a new PIN to unlock.'
                              : 'Age ${child.age}',
                          style: text.bodyMedium?.copyWith(
                            color: child.isLocked ? scheme.error : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activity.hasError && figures == null)
                  const InlineError("Couldn't load this child's screen time.")
                else ...[
                  _CapRow(
                    label: 'Today',
                    earned: figures?.earnedToday,
                    cap: figures?.dailyCapMinutes,
                    onSet: figures == null ? null : () => _setCap(context, ref, figures, daily: true),
                    button: 'Set daily cap',
                  ),
                  const SizedBox(height: 10),
                  _CapRow(
                    label: 'This week',
                    earned: figures?.earnedThisWeek,
                    cap: figures?.weeklyCapMinutes,
                    onSet: figures == null ? null : () => _setCap(context, ref, figures, daily: false),
                    button: 'Set weekly cap',
                  ),
                ],
                _NextAlarm(childId: child.id),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setCap(BuildContext context, WidgetRef ref, ChildActivity figures, {required bool daily}) async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => _CapDialog(
        title: daily ? 'Daily cap for ${child.name}' : 'Weekly cap for ${child.name}',
        explanation: daily
            ? 'The most screen time ${child.name} can earn in one day.'
            : 'The most screen time ${child.name} can earn in one week.',
        minutes: daily ? figures.dailyCapMinutes : figures.weeklyCapMinutes,
        max: daily ? math.max(240, figures.dailyCapMinutes) : math.max(1680, figures.weeklyCapMinutes),
        step: daily ? 15 : 30,
      ),
    );
    if (minutes == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(parentApiProvider).setCaps(
            child.id,
            dailyCapMinutes: daily ? minutes : null,
            weeklyCapMinutes: daily ? null : minutes,
          );
      // The caps, and the room left under them, are read again from the
      // server rather than guessed at here.
      ref.invalidate(activityProvider(child.id));
      ref.invalidate(ruleProvider(child.id));
      ref.invalidate(reportProvider(child.id));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            daily
                ? "${child.name}'s daily cap is now ${formatMinutes(minutes)}."
                : "${child.name}'s weekly cap is now ${formatMinutes(minutes)}.",
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The next quest alarm on this child's phone (PS-9): "Next: Mon 4:30 PM —
/// Sweep the floor". Worked out from the child's saved schedule, so it moves
/// as soon as the parent edits one.
class _NextAlarm extends ConsumerWidget {
  const _NextAlarm({required this.childId});

  final int childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(assignmentsProvider(childId)).value;
    if (assignments == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final next = nextQuestAlarm(assignments, now);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.alarm_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              next == null
                  ? 'No quest alarms set'
                  : 'Next: ${whenText(next.$2, now, MaterialLocalizations.of(context))} — ${next.$1.chore.name}',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// A day's or a week's earnings against its cap, with the button that changes
/// that cap.
class _CapRow extends StatelessWidget {
  const _CapRow({
    required this.label,
    required this.earned,
    required this.cap,
    required this.onSet,
    required this.button,
  });

  final String label;
  final int? earned;
  final int? cap;
  final VoidCallback? onSet;
  final String button;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tint = QuestColors.of(context).screenTime;
    final earned = this.earned;
    final cap = this.cap;
    final full = (earned == null || cap == null || cap <= 0) ? 0.0 : (earned / cap).clamp(0.0, 1.0).toDouble();
    final reached = earned != null && cap != null && cap > 0 && earned >= cap;

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A wrap, not a row: with large text on a narrow phone the button
          // moves under the figures instead of pushing them off the card.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                earned == null || cap == null
                    ? '$label …'
                    : '$label ${formatMinutes(earned)} of ${formatMinutes(cap)}',
                style: text.bodyMedium?.copyWith(
                  color: reached ? tint.ink : scheme.onSurfaceVariant,
                  fontWeight: reached ? FontWeight.w700 : null,
                ),
              ),
              TextButton(onPressed: onSet, child: Text(button)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: full,
              minHeight: 8,
              color: tint.ink,
              backgroundColor: tint.fill,
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks a cap in minutes. Returns the minutes, or null if nothing changed.
class _CapDialog extends StatefulWidget {
  const _CapDialog({
    required this.title,
    required this.explanation,
    required this.minutes,
    required this.max,
    required this.step,
  });

  final String title;
  final String explanation;
  final int minutes;
  final int max;
  final int step;

  @override
  State<_CapDialog> createState() => _CapDialogState();
}

class _CapDialogState extends State<_CapDialog> {
  late int _minutes = widget.minutes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(widget.title),
      // Scrolls, so large text on a short phone can still reach Save.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.explanation, style: text.bodyMedium),
            const SizedBox(height: 12),
            Text(
              formatMinutes(_minutes),
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Slider(
              value: _minutes.toDouble(),
              min: 0,
              max: widget.max.toDouble(),
              divisions: math.max(1, widget.max ~/ widget.step),
              label: formatMinutes(_minutes),
              onChanged: (raw) => setState(() => _minutes = (raw / widget.step).round() * widget.step),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_minutes), child: const Text('Save')),
      ],
    );
  }
}
