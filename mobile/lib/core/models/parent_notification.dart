import 'submission.dart';

/// What the photo checker decided about a photo when it arrived: the
/// ConfidenceRouter's routing, read from the server, never worked out here.
enum NotificationPriority {
  /// The checker was unsure and sent the photo to a grown-up.
  review,

  /// The checker approved the photo on its own.
  approved,

  /// The checker sent the photo back on its own.
  sentBack;

  static NotificationPriority parse(String? raw) => switch (raw) {
        'approved' => approved,
        'sent_back' => sentBack,
        // Anything unknown is treated as needing a look, never as settled.
        _ => review,
      };
}

/// One photo a child sent, as a notification for their parent.
class ParentNotification {
  const ParentNotification({
    required this.submission,
    required this.childAvatar,
    required this.priority,
    required this.unread,
  });

  factory ParentNotification.fromJson(Map<String, dynamic> json) =>
      ParentNotification(
        submission: Submission.fromJson(json),
        childAvatar: json['child_avatar'] as String? ?? '',
        priority: NotificationPriority.parse(json['priority'] as String?),
        unread: json['unread'] as bool? ?? false,
      );

  final Submission submission;
  final String childAvatar;
  final NotificationPriority priority;

  /// Sent since the parent last opened their notifications.
  final bool unread;

  /// Routed to a grown-up and still not decided: what the list puts first.
  bool get waitsForReview =>
      priority == NotificationPriority.review &&
      submission.status == SubmissionStatus.pending;
}

/// The feed: the latest photos, and how many arrived unseen.
class NotificationFeed {
  const NotificationFeed({required this.items, required this.unreadCount});

  factory NotificationFeed.fromJson(Map<String, dynamic> json) =>
      NotificationFeed(
        items: [
          for (final raw in (json['notifications'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
            ParentNotification.fromJson(raw),
        ],
        unreadCount: json['unread_count'] as int? ?? 0,
      );

  final List<ParentNotification> items;
  final int unreadCount;
}
