import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_notifier.dart';

/// Replaced in main() by a [LocalNotifier] once the plugin has started. Tests,
/// and a phone where it could not start, get silence.
final appNotifierProvider = Provider<AppNotifier>(
  (ref) => const SilentNotifier(),
);

/// Android system notifications, through flutter_local_notifications.
///
/// Every call is guarded. A notification is a convenience, and a failure to
/// show one must never take a screen down with it.
class LocalNotifier implements AppNotifier {
  LocalNotifier._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<NotificationTopic>.broadcast();
  bool _launchTaken = false;

  static const _channel = AndroidNotificationChannel(
    'chorequest_updates',
    'Photos and decisions',
    description: 'New chore photos to check, and what a grown-up decided.',
    importance: Importance.high,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Null when the plugin cannot start on this phone.
  static Future<LocalNotifier?> start() async {
    try {
      final notifier = LocalNotifier._(FlutterLocalNotificationsPlugin());
      await notifier._plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final topic = NotificationTopic.parse(response.payload);
          if (topic != null) notifier._taps.add(topic);
        },
      );
      await notifier._android?.createNotificationChannel(_channel);
      return notifier;
    } catch (error) {
      debugPrint('Notifications unavailable: $error');
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (error) {
      // Most likely another permission prompt is already on screen.
      debugPrint('Notification permission not requested: $error');
      return false;
    }
  }

  @override
  Future<void> show(AppNotification notification) async {
    try {
      await _plugin.show(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        payload: notification.topic.name,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            // Hidden on a locked screen: these name children and their chores.
            visibility: NotificationVisibility.private,
            color: const Color(0xFF1C6449),
          ),
        ),
      );
    } catch (error) {
      debugPrint('Notification not shown: $error');
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('Notifications not cleared: $error');
    }
  }

  @override
  Stream<NotificationTopic> get taps => _taps.stream;

  @override
  Future<NotificationTopic?> takeLaunchTopic() async {
    if (_launchTaken) return null;
    _launchTaken = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return NotificationTopic.parse(details.notificationResponse?.payload);
    } catch (error) {
      debugPrint('Launch notification not read: $error');
      return null;
    }
  }
}
