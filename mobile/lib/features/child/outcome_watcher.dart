import '../../core/models/submission.dart';
import '../../core/notifications/app_notifier.dart';
import 'child_api.dart';

/// Tells a child when a grown-up has decided one of their photos.
///
/// Used only while the app is in the background. On screen, the chore cards
/// already show the answer.
class OutcomeWatcher {
  OutcomeWatcher({required this.api, required this.notifier});

  final ChildApi api;
  final AppNotifier notifier;
  Map<int, SubmissionStatus>? _last;

  /// Starts afresh, so the next look only takes note. Anything decided before
  /// then the child has already seen on screen.
  void reset() => _last = null;

  /// Announces each photo whose status changed since the last look, and
  /// returns whether any photo is still waiting for a grown-up.
  Future<bool> look() async {
    final latest = await api.mySubmissions();
    final last = _last;
    _last = {for (final s in latest) s.id: s.status};

    if (last != null) {
      for (final s in latest) {
        final before = last[s.id];
        if (before != null &&
            before != s.status &&
            s.status != SubmissionStatus.pending) {
          await notifier.show(alertForOutcome(s, before: before));
        }
      }
    }
    return latest.any((s) => s.status == SubmissionStatus.pending);
  }
}

/// The notification a child sees when a grown-up decides a photo. Worded the
/// same gentle way as the result screen: a photo sent back is a request for a
/// new one, never a failure.
AppNotification alertForOutcome(
  Submission s, {
  required SubmissionStatus before,
}) {
  final chore = s.choreName ?? 'your chore';
  final (title, body) = switch (s.status) {
    SubmissionStatus.approved => (
        'Well done!',
        'A grown-up said yes to $chore.',
      ),
    SubmissionStatus.rejected when before == SubmissionStatus.approved => (
        "Let's try another photo",
        'A grown-up checked $chore again and asked for a new photo.',
      ),
    SubmissionStatus.rejected => (
        "Let's try another photo",
        'A grown-up asked for a new photo of $chore.',
      ),
    SubmissionStatus.pending => (
        'Your photo is waiting',
        'A grown-up will look at $chore soon.',
      ),
  };
  return AppNotification(
    id: s.id,
    title: title,
    body: body,
    topic: NotificationTopic.outcome,
  );
}
