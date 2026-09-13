import 'package:flutter/material.dart';

import '../../core/models/submission.dart';
import '../../shared/format.dart';

/// Where a photo stands, in the parent's words.
String decisionLabel(Submission s) => switch (s.parentDecision) {
      SubmissionStatus.approved => 'You approved it',
      SubmissionStatus.rejected => 'You sent it back',
      SubmissionStatus.pending || null => switch (s.routing) {
          Routing.autoApproved => 'Approved by the checker',
          Routing.autoRejected => 'Sent back by the checker',
          Routing.pendingReview => 'Waiting for you',
        },
    };

/// What the checker made of a photo.
String checkerLabel(Submission s) {
  final done = s.confidenceDone;
  if (done == null) return "The checker didn't look at this one.";
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
    final (background, foreground) = switch (submission.status) {
      SubmissionStatus.pending => (
          const Color(0xFFFFE9B8),
          const Color(0xFF6E4A00),
        ),
      SubmissionStatus.approved => (
          const Color(0xFFD5EFD8),
          const Color(0xFF1E5E2A),
        ),
      SubmissionStatus.rejected => (
          const Color(0xFFDCE6F2),
          const Color(0xFF274B6E),
        ),
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
