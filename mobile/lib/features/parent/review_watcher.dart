import '../../core/models/submission.dart';
import '../../core/notifications/app_notifier.dart';
import 'parent_api.dart';

/// The two lists behind the Review tab.
class ReviewFeed {
  const ReviewFeed({required this.waiting, required this.recent});

  /// Photos with no decision yet, newest first.
  final List<Submission> waiting;

  /// The latest photos of every kind, including those the checker decided.
  final List<Submission> recent;
}

/// Fetches the household's photos and announces the ones that are new.
///
/// Every new photo is announced, not only those waiting for a decision, so an
/// automatic approval never passes the parent by unseen. The first look only
/// takes note of what is there: signing in does not announce every photo
/// already in the queue.
class ReviewWatcher {
  ReviewWatcher({required this.api, required this.notifier});

  final ParentApi api;
  final AppNotifier notifier;
  Set<int>? _seen;

  Future<ReviewFeed> look() async {
    final lists = await Future.wait([
      api.reviews(),
      api.reviews(everything: true),
    ]);
    final feed = ReviewFeed(waiting: lists[0], recent: lists[1]);

    final seen = _seen;
    final arrived = <int, Submission>{
      for (final s in [...feed.waiting, ...feed.recent])
        if (seen != null && !seen.contains(s.id)) s.id: s,
    };
    _seen = {
      ...?seen,
      for (final s in feed.waiting) s.id,
      for (final s in feed.recent) s.id,
    };

    if (arrived.isNotEmpty) {
      await notifier.show(alertForArrivals(arrived.values.toList()));
    }
    return feed;
  }
}

/// The notification for photos that have just arrived.
AppNotification alertForArrivals(List<Submission> arrived) {
  if (arrived.length == 1) {
    final s = arrived.single;
    return AppNotification(
      id: s.id,
      title: '${s.childName ?? 'Your child'}: ${s.choreName ?? 'a chore'}',
      body: switch (s.routing) {
        Routing.pendingReview => 'A photo is waiting for you to check.',
        Routing.autoApproved => 'The checker approved this photo.',
        Routing.autoRejected => 'The checker sent this photo back.',
      },
      topic: NotificationTopic.review,
    );
  }

  final waiting =
      arrived.where((s) => s.status == SubmissionStatus.pending).length;
  final from = _joined({for (final s in arrived) s.childName ?? 'your child'});
  return AppNotification(
    // Submission ids start at 1, so a summary never replaces a single photo's
    // notification, only the previous summary.
    id: 0,
    title: '${arrived.length} new photos',
    body: switch (waiting) {
      0 => 'From $from. The checker decided all of them.',
      1 => 'From $from. 1 is waiting for you to check.',
      _ => 'From $from. $waiting are waiting for you to check.',
    },
    topic: NotificationTopic.review,
  );
}

/// "Mia", "Mia and Leo", "Mia, Leo and Ana".
String _joined(Set<String> names) {
  final list = names.toList();
  if (list.length == 1) return list.single;
  return '${list.take(list.length - 1).join(', ')} and ${list.last}';
}
