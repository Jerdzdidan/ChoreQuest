import 'package:flutter/material.dart';

import '../../core/models/submission.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';

/// Where a quest stands, in the parent's words. A quest session waits for
/// the parent until they decide; only older single photos were ever decided
/// automatically.
String decisionLabel(Submission s) => switch (s.parentDecision) {
      SubmissionStatus.approved => 'You approved it',
      SubmissionStatus.rejected => 'You sent it back',
      SubmissionStatus.pending || null => s.isSession
          ? 'Waiting for you'
          : switch (s.routing) {
              Routing.autoApproved => 'Approved automatically',
              Routing.autoRejected => 'Sent back automatically',
              Routing.pendingReview => 'Waiting for you',
            },
    };

/// For an older quest sent as one photo: what the automatic check made of
/// it.
String photoCheckLabel(Submission s) {
  final done = s.confidenceDone;
  if (done == null) return 'No automatic check ran on this photo.';
  return '${formatPercent(done)} sure the chore is done.';
}

/// Whether the verdict came from the debug stand-in rather than the trained
/// model. Those rows are left out of the study's results.
bool isStandIn(Submission s) => s.modelVersion?.startsWith('stub') ?? false;

/// "Today, 3:42 PM", "Yesterday, 9:05 AM", "Sep 8, 6:30 PM".
String sentLabel(BuildContext context, DateTime at) {
  final local = at.toLocal();
  final time = TimeOfDay.fromDateTime(local).format(context);
  final days = DateUtils.dateOnly(DateTime.now())
      .difference(DateUtils.dateOnly(local))
      .inDays;
  return switch (days) {
    0 => 'Today, $time',
    1 => 'Yesterday, $time',
    _ => '${MaterialLocalizations.of(context).formatShortMonthDay(local)}, $time',
  };
}

/// A small label for where a photo stands: amber while waiting, green when
/// approved, blue when sent back.
class DecisionChip extends StatelessWidget {
  const DecisionChip({super.key, required this.submission});

  final Submission submission;

  @override
  Widget build(BuildContext context) {
    final colors = QuestColors.of(context);
    final (fill: background, ink: foreground) = switch (submission.status) {
      SubmissionStatus.pending => colors.review,
      SubmissionStatus.approved => colors.approved,
      SubmissionStatus.rejected => colors.saved,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        decisionLabel(submission),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
