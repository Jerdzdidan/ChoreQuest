/// What a notification is about, and so where a tap on it leads.
enum NotificationTopic {
  /// New photos for a parent to check.
  review,

  /// A grown-up's decision on a child's photo.
  outcome;

  static NotificationTopic? parse(String? raw) {
    for (final topic in values) {
      if (topic.name == raw) return topic;
    }
    return null;
  }
}

/// A notification, worded by the app.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.topic,
  });

  /// Showing another notification with the same id replaces this one.
  final int id;
  final String title;
  final String body;
  final NotificationTopic topic;
}

/// Shows notifications on this phone.
///
/// These are local notifications, raised by the app itself when a refresh
/// finds something new. ChoreQuest has no push server, so a phone hears of a
/// new photo or a decision only while the app is running: on screen, or in the
/// background for as long as Android lets it keep running. Once Android stops
/// the app, nothing arrives until it is opened again.
///
/// Free of Flutter imports, so the code that decides what to announce runs
/// under plain Dart against the real API.
abstract interface class AppNotifier {
  /// Asks for permission where Android requires it, from Android 13 on.
  /// Returns whether notifications may be shown.
  Future<bool> requestPermission();

  Future<void> show(AppNotification notification);

  /// Removes every notification this app has shown, so nothing about one
  /// account is left in the shade for the next person to sign in.
  Future<void> clearAll();

  /// Taps on notifications while the app is running.
  Stream<NotificationTopic> get taps;

  /// The notification whose tap started the app, if one did. Answers only
  /// once, so the same tap is not acted on twice.
  Future<NotificationTopic?> takeLaunchTopic();
}

/// Shows nothing. Used in tests, and on a phone where notifications could not
/// be started.
class SilentNotifier implements AppNotifier {
  const SilentNotifier();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> show(AppNotification notification) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Stream<NotificationTopic> get taps => const Stream.empty();

  @override
  Future<NotificationTopic?> takeLaunchTopic() async => null;
}
