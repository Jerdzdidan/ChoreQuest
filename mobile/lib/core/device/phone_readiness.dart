import 'dart:convert';
import 'dart:io';

/// What quest alarms need on the child's phone (DV-1), each a row that is
/// green or red, with what will not work while it is red, in plain words.
/// The keys are what the server stores (BE-9).
enum ReadinessRow {
  notifications(
    'notifications',
    'Notifications',
    'Alarms cannot ring or show their quest.',
    'Turn on notifications',
  ),
  exactAlarms(
    'exact_alarms',
    'Alarms on the minute',
    'Alarms may ring late.',
    'Allow exact alarms',
  ),
  fullScreen(
    'full_screen',
    'Quest page over the lock screen',
    'The quest page will not open by itself; the alarm only shows as a notification.',
    'Allow the full-screen page',
  ),
  battery(
    'battery',
    'Not put to sleep by battery saving',
    'The phone may put ChoreQuest to sleep, and then alarms do not ring at all.',
    'Turn off battery saving for ChoreQuest',
  ),
  camera(
    'camera',
    'Camera',
    'Quests cannot start: the camera takes the Before and After photos.',
    'Allow the camera',
  );

  const ReadinessRow(this.key, this.title, this.whenOff, this.fixLabel);

  final String key;
  final String title;

  /// What will not work while this row is red.
  final String whenOff;

  /// The button that opens what fixes it.
  final String fixLabel;
}

/// One check of the phone: each row's state, and whether the maker has its
/// own battery manager that can still stop a sleeping app.
class ReadinessResult {
  const ReadinessResult({
    required this.rows,
    required this.checkedAt,
    this.makerBattery = false,
  });

  factory ReadinessResult.fromJson(Map<String, dynamic> json) => ReadinessResult(
        rows: {
          for (final row in ReadinessRow.values) row: json[row.key] == true,
        },
        checkedAt: DateTime.tryParse(json['checked_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        makerBattery: json['maker_battery'] == true,
      );

  final Map<ReadinessRow, bool> rows;
  final DateTime checkedAt;
  final bool makerBattery;

  bool isOn(ReadinessRow row) => rows[row] ?? false;

  /// Every row green.
  bool get ready => ReadinessRow.values.every(isOn);

  List<ReadinessRow> get off => [for (final row in ReadinessRow.values) if (!isOn(row)) row];

  /// What POST /my/device-status takes.
  Map<String, bool> get checks => {for (final row in ReadinessRow.values) row.key: isOn(row)};

  Map<String, dynamic> toJson() => {
        ...checks,
        'maker_battery': makerBattery,
        'checked_at': checkedAt.toUtc().toIso8601String(),
      };
}

/// What happened when a row's Fix was tapped.
enum FixOutcome {
  /// Android's own prompt was shown and the permission given.
  granted,

  /// The prompt was shown and refused; it can be asked again.
  denied,

  /// A settings screen opened; the row is checked again on return.
  opened,

  /// No screen for it on this phone.
  unavailable;

  static FixOutcome parse(String? raw) => switch (raw) {
        'granted' => granted,
        'denied' => denied,
        'opened' => opened,
        _ => unavailable,
      };
}

/// Reads the rows from the phone and opens what fixes them; the Android
/// side lives in MainActivity.
abstract class ReadinessProbe {
  /// Null where the phone cannot say (not Android, or a test).
  Future<ReadinessResult?> check();

  Future<FixOutcome> fix(ReadinessRow row);

  /// The maker's own battery manager, where one is known.
  Future<FixOutcome> openMakerBattery();
}

/// The last check, kept in the app's own files: whether this phone has been
/// through the checklist before, and what it found.
class ReadinessStore {
  ReadinessStore(this.file);

  final File file;

  Future<void> save(ReadinessResult result) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(result.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<ReadinessResult?> load() async {
    try {
      if (!await file.exists()) return null;
      return ReadinessResult.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

/// Checks the phone, keeps the result and tells the server (DV-10), with
/// when the schedule was last copied, so the parent's Board can say Ready or
/// Needs setup.
class PhoneReadinessService {
  PhoneReadinessService({
    required this.probe,
    required this.store,
    required this.report,
    required this.lastSync,
  });

  final ReadinessProbe probe;
  final ReadinessStore store;

  /// POST /my/device-status.
  final Future<void> Function(Map<String, bool> checks, DateTime? lastSyncAt) report;

  /// When the schedule was last fetched (DV-3), or null if never.
  final Future<DateTime?> Function() lastSync;

  /// The phone's state now, and whether this is its first check, or null
  /// where the phone cannot say. A report that cannot be sent is tried again
  /// at the next check.
  Future<({ReadinessResult result, bool firstRun})?> refresh() async {
    final result = await probe.check();
    if (result == null) return null;
    final firstRun = await store.load() == null;
    try {
      await store.save(result);
    } catch (_) {
      // Only remembering it failed; the report still goes.
    }
    try {
      await report(result.checks, await lastSync());
    } catch (_) {
      // Offline: the parent sees the last report until the next one.
    }
    return (result: result, firstRun: firstRun);
  }
}
