import 'dart:convert';

import 'package:alarm/alarm.dart';

import '../../shared/ringtones.dart';
import 'quest_alarm_service.dart';

/// The alarm plugin (DV-4): a foreground service with the system alarm
/// manager, so an alarm rings with the app closed and the screen locked,
/// opens the full-screen ring page, loops its sound and vibrates.
class PluginAlarmBackend implements AlarmBackend {
  const PluginAlarmBackend();

  @override
  Future<bool> set(QuestAlarm alarm) => Alarm.set(
        alarmSettings: AlarmSettings(
          id: alarm.assignmentId,
          dateTime: alarm.at,
          assetAudioPath: alarm.ringtoneAsset,
          loopAudio: true,
          vibrate: true,
          androidFullScreenIntent: true,
          // Swiping the app away must not silence it: only the session does
          // (DV-6), or the safety net (DV-7).
          androidStopAlarmOnTermination: false,
          warningNotificationOnKill: true,
          // From quiet to full over the ramp, not full at once: the users
          // are four to ten.
          volumeSettings: VolumeSettings.fade(fadeDuration: rampUp),
          notificationSettings: NotificationSettings(
            title: 'Time for a quest!',
            body: '${alarm.choreName}. Open ChoreQuest and tap Start.',
            // No stop button, and a swipe puts it straight back: the
            // notification shade is not a way out.
            stopButton: null,
            androidStopAlarmOnDismiss: false,
          ),
          payload: jsonEncode({'assignment_id': alarm.assignmentId}),
        ),
      );

  @override
  Future<bool> remove(int assignmentId) => Alarm.stop(assignmentId);

  @override
  Future<Set<int>> scheduledIds() async => {for (final alarm in await Alarm.getAlarms()) alarm.id};

  @override
  Future<bool> isRinging(int assignmentId) => Alarm.isRinging(assignmentId);

  @override
  Stream<Set<int>> get ringing => Alarm.ringing.map((set) => {for (final alarm in set.alarms) alarm.id});
}
