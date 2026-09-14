import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/balance.dart';
import '../../core/models/child_progress.dart';
import '../../core/models/chore.dart';
import '../../core/models/submission.dart';
import '../../core/session/session_controller.dart';
import '../../core/uploads/pending_upload.dart';
import '../../core/uploads/upload_queue.dart';
import '../../core/verification/chore_verifier.dart';
import 'child_api.dart';
import 'upload_sync.dart';

final childApiProvider = Provider<ChildApi>(
  (ref) => ChildApi(ref.watch(apiClientProvider)),
);

// autoDispose for the same reason as the parent's data: the ProviderScope
// outlives a sign-out, and a brother or sister signing in next on the same
// phone must never be shown these.

final todayChoresProvider = FutureProvider.autoDispose<TodayChores>(
  (ref) => ref.watch(childApiProvider).today(),
);

final balanceProvider = FutureProvider.autoDispose<Balance>(
  (ref) => ref.watch(childApiProvider).balance(),
);

final mySubmissionsProvider = FutureProvider.autoDispose<List<Submission>>(
  (ref) => ref.watch(childApiProvider).mySubmissions(),
);

final progressProvider = FutureProvider.autoDispose<ChildProgress>(
  (ref) => ref.watch(childApiProvider).progress(),
);

/// Kept for the app's lifetime, so a tester's chosen stand-in outcome survives
/// from one photo to the next. Slice 5.3 replaces it with the real model.
final choreVerifierProvider = Provider<ChoreVerifier>(
  (ref) => StubVerifier(enabled: kDebugMode),
);

/// Where photos wait until the server has them. Set in main() to a folder in
/// the app's private storage, which Android does not clear the way it clears
/// the camera's cache.
final uploadQueueProvider = Provider<UploadQueue>(
  (ref) => throw UnimplementedError('uploadQueueProvider is set in main().'),
);

/// Sends one child's saved photos, with that child's sign-in fixed for the
/// whole send. If the phone changes hands halfway, a photo still goes up under
/// the child who took it, never under a brother's or sister's token.
final uploadSyncProvider = Provider.family<UploadSync, String>(
  (ref, token) => UploadSync(
    queue: ref.watch(uploadQueueProvider),
    api: ChildApi(ApiClient(readToken: () async => token)),
  ),
);

/// This child's photos still saved on the phone, waiting to send.
final pendingUploadsProvider =
    FutureProvider.autoDispose.family<List<PendingUpload>, int>(
  (ref, childId) => ref.watch(uploadQueueProvider).forChild(childId),
);

/// Refetches everything the child's home screen shows.
void refreshChildData(WidgetRef ref) {
  ref.invalidate(todayChoresProvider);
  ref.invalidate(balanceProvider);
  ref.invalidate(mySubmissionsProvider);
  ref.invalidate(progressProvider);
  ref.invalidate(pendingUploadsProvider);
}

enum ChoreState { toDo, waiting, queued, done, tryAgain }

/// Where one chore stands today, from the photos already sent for it and any
/// still saved on the phone.
///
/// An approval anywhere today wins. Failing that, a photo saved on the phone
/// and not yet sent; then one waiting for a grown-up; then one sent back.
ChoreState choreStateFor(
  Assignment assignment,
  List<Submission> sent,
  DateTime today, {
  List<PendingUpload> saved = const [],
}) {
  final todays = sent.where(
    (s) => s.assignmentId == assignment.id && _sameDay(s.forDate, today),
  );
  if (todays.any((s) => s.status == SubmissionStatus.approved)) {
    return ChoreState.done;
  }
  if (saved.any((u) => u.assignmentId == assignment.id)) {
    return ChoreState.queued;
  }
  if (todays.any((s) => s.status == SubmissionStatus.pending)) {
    return ChoreState.waiting;
  }
  if (todays.any((s) => s.status == SubmissionStatus.rejected)) {
    return ChoreState.tryAgain;
  }
  return ChoreState.toDo;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
