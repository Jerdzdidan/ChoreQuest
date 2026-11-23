import 'submission.dart';

/// How much a finished quest needs the parent's eye, as the server works it
/// out (BE-5), never here.
enum NotificationPriority {
  /// A quest session whose evidence is weak: look closely.
  checkCarefully,

  /// A quest session whose evidence is strong.
  looksGenuine,

  /// A quest session no model checks, such as a custom chore.
  manualCheck,

  /// An older single photo the automatic check left to a grown-up.
  review,

  /// An older single photo approved automatically.
  approved,

  /// An older single photo sent back automatically.
  sentBack;

  static NotificationPriority parse(String? raw) => switch (raw) {
        'check_carefully' => checkCarefully,
        'looks_genuine' => looksGenuine,
        'manual_check' => manualCheck,
        'approved' => approved,
        'sent_back' => sentBack,
        // Anything unknown is treated as needing a look, never as settled.
        _ => review,
      };

  /// Listed first among those waiting: the ones to look at most closely.
  int get urgency => switch (this) {
        checkCarefully => 0,
        review => 1,
        manualCheck => 2,
        looksGenuine => 3,
        approved || sentBack => 4,
      };
}

/// One quest a child finished, as a notification for their parent.
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

  /// Still waiting for the parent's decision: what the list puts first. A
  /// quest session always waits, since nothing is approved without them.
  bool get waitsForReview => submission.status == SubmissionStatus.pending;
}

/// Something that happened to a quest alarm (BE-10, DV-7, DV-12).
enum AlarmEventKind {
  /// A grown-up stopped it with their password.
  override,

  /// It rang its longest and stopped itself; the quest counts as missed.
  timedOut,

  /// The scheduled third-party camera was missing, so the phone was used.
  cameraMissing;

  static AlarmEventKind parse(String? raw) => switch (raw) {
        'timed_out' => timedOut,
        'camera_missing' => cameraMissing,
        _ => override,
      };
}

/// An alarm event, as a notification for the parent.
class AlarmNotification {
  const AlarmNotification({
    required this.id,
    required this.kind,
    required this.childName,
    required this.childAvatar,
    required this.chore,
    required this.at,
    required this.unread,
  });

  factory AlarmNotification.fromJson(Map<String, dynamic> json) => AlarmNotification(
        id: json['id'] as int,
        kind: AlarmEventKind.parse(json['kind'] as String?),
        childName: json['child_name'] as String? ?? 'Your child',
        childAvatar: json['child_avatar'] as String? ?? '',
        chore: json['chore'] as String?,
        at: DateTime.parse(json['at'] as String),
        unread: json['unread'] as bool? ?? false,
      );

  final int id;
  final AlarmEventKind kind;
  final String childName;
  final String childAvatar;
  final String? chore;
  final DateTime at;
  final bool unread;
}

/// The feed: the latest quests, the alarm events, and how many arrived
/// unseen.
class NotificationFeed {
  const NotificationFeed({required this.items, required this.unreadCount, this.alarms = const []});

  factory NotificationFeed.fromJson(Map<String, dynamic> json) =>
      NotificationFeed(
        items: [
          for (final raw in (json['notifications'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
            ParentNotification.fromJson(raw),
        ],
        alarms: [
          for (final raw in (json['alarms'] as List? ?? const []).cast<Map<String, dynamic>>())
            AlarmNotification.fromJson(raw),
        ],
        unreadCount: json['unread_count'] as int? ?? 0,
      );

  final List<ParentNotification> items;
  final List<AlarmNotification> alarms;
  final int unreadCount;
}
