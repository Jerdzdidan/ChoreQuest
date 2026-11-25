import '../../core/models/parent_notification.dart';
import '../../core/notifications/app_notifier.dart';

/// What the parent is told about a phone where App Lock is not working now
/// (AL-4, rule 10), in the list and on their phone.
String appLockLine(AppLockNotification n) {
  switch (n.trouble) {
    case AppLockTrouble.needsAttention:
      final titles = n.missingTitles;
      final what = titles.isEmpty ? 'Something App Lock needs' : _joined(titles);
      final verb = titles.length == 1 ? 'is' : 'are';
      return 'App Lock needs you on ${n.phoneName}: $what $verb off. '
          'Turn ${titles.length == 1 ? 'it' : 'them'} back on in ChoreQuest on that phone.';
    case AppLockTrouble.silent:
      return "App Lock on ${n.phoneName} hasn't checked in. ChoreQuest may have been stopped or removed, "
          'or the phone is off or offline.';
  }
}

/// A notification for a phone that has just stopped working. A tap opens
/// the notification list, like a new photo's.
AppNotification alertForAppLock(AppLockNotification n) => AppNotification(
      // Its own range, apart from photos' ids, one per phone: a newer
      // trouble on the same phone replaces the last.
      id: 0x7A000000 | (n.deviceKey.hashCode & 0xFFFFFF),
      title: switch (n.trouble) {
        AppLockTrouble.needsAttention => 'App Lock needs you',
        AppLockTrouble.silent => 'App Lock went quiet',
      },
      body: appLockLine(n),
      topic: NotificationTopic.review,
    );

/// The phones that have newly stopped working since the last look.
List<AppLockNotification> newAppLockTrouble(List<AppLockNotification> before, List<AppLockNotification> after) {
  String key(AppLockNotification n) => '${n.deviceKey}|${n.trouble.name}|${n.since.toIso8601String()}';
  final seen = {for (final n in before) key(n)};
  return [for (final n in after) if (n.unread && !seen.contains(key(n))) n];
}

String _joined(List<String> names) {
  if (names.length == 1) return names.single;
  return '${names.take(names.length - 1).join(', ')} and ${names.last}';
}
