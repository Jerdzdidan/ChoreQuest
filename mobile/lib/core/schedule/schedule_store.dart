import 'dart:convert';
import 'dart:io';

import '../models/chore.dart';

/// The child's schedule as the server last sent it (BE-7), with when it was
/// fetched: every active quest with its weekdays, alarm, ringtone and camera.
class ScheduleSnapshot {
  const ScheduleSnapshot({
    required this.assignments,
    required this.timezone,
    required this.fetchedAt,
    this.serverTime,
  });

  factory ScheduleSnapshot.fromJson(Map<String, dynamic> json) => ScheduleSnapshot(
        assignments: [
          for (final raw in (json['assignments'] as List? ?? const []).cast<Map<String, dynamic>>())
            Assignment.fromJson(raw),
        ],
        timezone: json['timezone'] as String? ?? '',
        serverTime: DateTime.tryParse(json['server_time'] as String? ?? ''),
        fetchedAt: DateTime.tryParse(json['fetched_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final List<Assignment> assignments;

  /// The household's timezone, which the alarms ring in.
  final String timezone;
  final DateTime? serverTime;

  /// When the phone last reached the server for it.
  final DateTime fetchedAt;
}

/// Keeps the schedule in a JSON file in the app's own files (DV-2), so the
/// alarms can be armed again with no connection: after the app is killed,
/// after the phone restarts, or on a day without Wi-Fi.
///
/// Written to a fresh file and renamed over the old one, so a crash part-way
/// leaves the previous schedule whole.
class ScheduleStore {
  ScheduleStore(this.file);

  final File file;

  /// Saves what the server sent, stamped with when it arrived.
  Future<void> save(Map<String, dynamic> fromServer, DateTime fetchedAt) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({...fromServer, 'fetched_at': fetchedAt.toUtc().toIso8601String()}), flush: true);
    await temp.rename(file.path);
  }

  /// The last schedule saved, or null when there is none or it cannot be
  /// read.
  Future<ScheduleSnapshot?> load() async {
    try {
      if (!await file.exists()) return null;
      return ScheduleSnapshot.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
