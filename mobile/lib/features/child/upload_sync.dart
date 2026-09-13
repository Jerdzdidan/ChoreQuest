import 'dart:io';

import '../../core/api/api_exception.dart';
import '../../core/models/submission.dart';
import '../../core/uploads/pending_upload.dart';
import '../../core/uploads/upload_queue.dart';
import 'child_api.dart';

enum UploadOutcome {
  /// The server has it.
  sent,

  /// Turned down for good, such as a chore already finished today. The photo
  /// has been dropped, because retrying cannot change the answer.
  refused,

  /// Did not get through. Still queued, and will be tried again.
  waiting,
}

class UploadResult {
  const UploadResult({
    required this.upload,
    required this.outcome,
    this.submission,
    this.message,
  });

  final PendingUpload upload;
  final UploadOutcome outcome;
  final Submission? submission;
  final String? message;
}

/// Delivers queued photos, oldest first, each exactly once.
///
/// Exactly once rests on two things together. A photo leaves the queue only
/// after the server has answered for it. And every attempt carries the same
/// client token, so if the app dies after the server accepted a photo but
/// before the queue forgot it, the retry is answered with the original
/// submission instead of creating a second one.
class UploadSync {
  UploadSync({required this.queue, required this.api});

  final UploadQueue queue;
  final ChildApi api;

  final _inFlight = <int, Future<List<UploadResult>>>{};

  /// Sends what is waiting for this child. A second call while one is running
  /// joins it rather than starting a parallel send of the same photos.
  Future<List<UploadResult>> flush({required int childId}) {
    final running = _inFlight[childId];
    if (running != null) return running;

    // A block, not an arrow: remove() returns this very future, and
    // whenComplete waits on a returned future, so an arrow would never finish.
    final started = _flush(childId).whenComplete(() {
      _inFlight.remove(childId);
    });
    _inFlight[childId] = started;
    return started;
  }

  Future<List<UploadResult>> _flush(int childId) async {
    final waiting = await queue.forChild(childId)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final results = <UploadResult>[];
    for (final upload in waiting) {
      final result = await send(upload);
      results.add(result);
      // No connection for this one means none for the next either.
      if (result.outcome == UploadOutcome.waiting) break;
    }
    return results;
  }

  Future<UploadResult> send(PendingUpload upload) async {
    try {
      final response = await api.submit(
        OutgoingSubmission(
          clientToken: upload.clientToken,
          assignmentId: upload.assignmentId,
          photoPath: upload.photoPath,
          label: upload.label,
          confidence: upload.confidence,
          modelVersion: upload.modelVersion,
          inferenceMs: upload.inferenceMs,
        ),
      );
      await queue.remove(upload.clientToken);
      return UploadResult(
        upload: upload,
        outcome: UploadOutcome.sent,
        submission: response.submission,
      );
    } on ApiRejected catch (e) {
      await queue.remove(upload.clientToken);
      return UploadResult(
        upload: upload,
        outcome: UploadOutcome.refused,
        message: e.errorFor('assignment_id') ?? e.message,
      );
    } on FileSystemException {
      await queue.remove(upload.clientToken);
      return UploadResult(
        upload: upload,
        outcome: UploadOutcome.refused,
        message: 'The photo could not be found. Please take it again.',
      );
    } on ApiException catch (e) {
      // Unreachable, a server fault, too many attempts, or a sign-in that has
      // lapsed. Every one of these can come right, so the photo keeps waiting.
      await queue.recordFailure(upload.clientToken, e.message);
      return UploadResult(
        upload: upload,
        outcome: UploadOutcome.waiting,
        message: e.message,
      );
    }
  }
}
