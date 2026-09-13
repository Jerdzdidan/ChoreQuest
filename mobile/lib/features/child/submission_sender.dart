import 'dart:io';

import '../../core/models/chore.dart';
import '../../core/models/submission.dart';
import '../../core/uploads/pending_upload.dart';
import '../../core/uploads/upload_queue.dart';
import '../../core/verification/chore_verifier.dart';
import 'upload_sync.dart';

/// What happened when a photo was sent.
sealed class SendOutcome {
  const SendOutcome();
}

/// The server has it, whether from this attempt or an earlier one carrying the
/// same client token.
final class Sent extends SendOutcome {
  const Sent(this.submission);

  final Submission submission;
}

/// The server turned it down for a reason trying again will not change, such
/// as the chore already being finished today.
final class Refused extends SendOutcome {
  const Refused(this.message);

  final String message;
}

/// It did not get through and is saved on the phone. It goes by itself once
/// the connection is back, carrying the same client token, so it can never
/// arrive twice.
final class Queued extends SendOutcome {
  const Queued(this.message);

  /// Why it did not get through, for a grown-up rather than the child.
  final String message;
}

/// Saves a photo in the upload queue, then tries to send it straight away.
///
/// Saved first, so a photo that cannot go now is not lost, and one whose send
/// is cut off when the app is closed goes up on the next attempt.
Future<SendOutcome> queueAndSend({
  required UploadQueue queue,
  required UploadSync sync,
  required int childId,
  required Assignment assignment,
  required String photoPath,
  required String clientToken,
  required Verdict verdict,
}) async {
  final PendingUpload upload;
  try {
    upload = await queue.enqueue(
      clientToken: clientToken,
      childId: childId,
      assignmentId: assignment.id,
      choreName: assignment.chore.name,
      sourcePhotoPath: photoPath,
      label: verdict.label,
      confidence: verdict.confidence,
      modelVersion: verdict.modelVersion,
      inferenceMs: verdict.inferenceMs,
    );
  } on FileSystemException {
    return const Refused(
      'The photo could not be saved on this phone. Free up some space, then '
      'take it again.',
    );
  }

  final result = await sync.send(upload);
  return switch (result.outcome) {
    UploadOutcome.sent => Sent(result.submission!),
    UploadOutcome.refused =>
      Refused(result.message ?? 'This photo was not accepted.'),
    UploadOutcome.waiting => Queued(result.message ?? 'No connection.'),
  };
}
