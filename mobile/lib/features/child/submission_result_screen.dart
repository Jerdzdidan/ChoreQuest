import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chore.dart';
import '../../core/models/submission.dart';
import '../../shared/format.dart';
import 'child_providers.dart';
import 'chore_camera_screen.dart';
import 'submission_sender.dart';

/// What happened to the photo, told gently.
///
/// A photo the checker could not accept is never framed as the child having
/// failed or lied: it is "hard to see", and a grown-up can still say yes.
class SubmissionResultScreen extends ConsumerWidget {
  const SubmissionResultScreen({
    super.key,
    required this.assignment,
    required this.outcome,
  });

  final Assignment assignment;
  final SendOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final status = switch (outcome) {
      Sent(:final submission) => submission.status,
      _ => null,
    };

    final (icon, colour, title, message) = switch (outcome) {
      Sent() when status == SubmissionStatus.approved => (
          Icons.celebration_rounded,
          const Color(0xFF2E7D32),
          'You did it!',
          'Your screen time went up.',
        ),
      Sent() when status == SubmissionStatus.rejected => (
          Icons.image_search_rounded,
          const Color(0xFF1D4A73),
          "Let's try another photo",
          "It's hard to see that it's finished. Take a new photo, or ask a "
              'grown-up to check it.',
        ),
      Sent() => (
          Icons.hourglass_top_rounded,
          const Color(0xFF9A6412),
          'Great job!',
          'A grown-up will look at your photo soon.',
        ),
      Refused(:final message) => (
          Icons.info_rounded,
          scheme.primary,
          'This photo was not sent',
          message,
        ),
      // Why it did not get through is for a grown-up. What the child needs to
      // know is that the photo is safe and nothing more needs doing.
      Queued() => (
          Icons.cloud_upload_rounded,
          const Color(0xFF1D4A73),
          'Your photo is saved',
          'It will send by itself when the phone is online again.',
        ),
    };

    final balance = status == SubmissionStatus.approved
        ? ref.watch(balanceProvider)
        : null;
    final current =
        balance != null && balance.hasValue ? balance.requireValue : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colour.withValues(alpha: 0.14),
                    ),
                    child: Icon(icon, size: 76, color: colour),
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center, style: text.titleMedium),
                if (current != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'You have ${formatMinutes(current.spendableMinutes)} of screen time.',
                    textAlign: TextAlign.center,
                    style: text.titleLarge?.copyWith(color: colour),
                  ),
                  if (current.earningBlocked)
                    Text(
                      "That's all the screen time you can earn for now.",
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                ],
                const SizedBox(height: 32),
                if (status == SubmissionStatus.rejected) ...[
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ChoreCameraScreen(assignment: assignment),
                      ),
                    ),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: const Text('Take another photo'),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
                  child: const Text('Back to my quests'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
