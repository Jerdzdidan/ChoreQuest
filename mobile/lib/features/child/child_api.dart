import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/models/api_dates.dart';
import '../../core/models/balance.dart';
import '../../core/models/camera.dart';
import '../../core/models/child_progress.dart';
import '../../core/models/family_quest.dart';
import '../../core/models/chore.dart';
import '../../core/models/cosmetics.dart';
import '../../core/models/submission.dart';

class TodayChores {
  const TodayChores({required this.date, required this.chores});

  /// The server's idea of today, which is the day submissions count against.
  final DateTime date;
  final List<Assignment> chores;
}

class SubmitResult {
  const SubmitResult({required this.submission, required this.duplicate});

  final Submission submission;

  /// The server had already accepted this exact upload and returned it again.
  final bool duplicate;
}

/// A photo and what the checker made of it, ready to send.
class OutgoingSubmission {
  const OutgoingSubmission({
    required this.clientToken,
    required this.assignmentId,
    required this.photoPath,
    this.label,
    this.confidence,
    this.modelVersion,
    this.inferenceMs,
  });

  final String clientToken;
  final int assignmentId;
  final String photoPath;
  final String? label;
  final double? confidence;
  final String? modelVersion;
  final int? inferenceMs;
}

/// A finished quest session, ready to send (LS-9).
class OutgoingSession {
  const OutgoingSession({
    required this.clientToken,
    required this.assignmentId,
    required this.beforePath,
    required this.afterPath,
    required this.evidence,
  });

  final String clientToken;
  final int assignmentId;
  final String beforePath;
  final String afterPath;
  final Map<String, Object?> evidence;
}

/// Everything the child's screens ask of the server, typed.
///
/// Free of Flutter imports, so it runs under plain Dart against the real API.
class ChildApi {
  const ChildApi(this._api);

  final ApiClient _api;

  Future<TodayChores> today() async {
    final body = await _api.get('/my/chores');
    return TodayChores(
      date: parseApiDate(body['date'] as String),
      chores: _list(body['chores'], Assignment.fromJson),
    );
  }

  Future<List<Submission>> mySubmissions() async {
    final body = await _api.get('/my/submissions');
    return _list(body['submissions'], Submission.fromJson);
  }

  Future<Balance> balance() async => Balance.fromJson(await _api.get('/my/balance'));

  Future<ChildProgress> progress() async =>
      ChildProgress.fromJson(await _api.get('/my/progress'));

  /// The quests the whole household is working on together (F3).
  Future<List<FamilyQuest>> familyQuests() async {
    final body = await _api.get('/my/family-quests');
    return [
      for (final raw in (body['family_quests'] as List? ?? const []).cast<Map<String, dynamic>>())
        FamilyQuest.fromJson(raw),
    ];
  }

  /// Everything the child has unlocked.
  Future<Wardrobe> cosmetics() async =>
      Wardrobe.fromJson(await _api.get('/my/cosmetics'));

  /// Reports cosmetics the child's level has unlocked. Items the server
  /// already holds are left as they are.
  Future<Wardrobe> recordUnlocked(
    List<(CosmeticCategory, String)> items,
  ) async =>
      Wardrobe.fromJson(
        await _api.post(
          '/my/cosmetics',
          body: {
            'items': [
              for (final (category, key) in items)
                {'category': category.name, 'key': key},
            ],
          },
        ),
      );

  /// Puts on an item the child owns, taking off whatever else was on in that
  /// category. Refused with a field error on `key` when the child has not
  /// unlocked it.
  /// Tells the server every camera this phone can see right now, replacing
  /// what it said before (BE-8, DV-9). The parent's phone offers a
  /// third-party camera only while one is reported as connected.
  Future<List<ReportedCamera>> reportCameras(String deviceKey, List<ReportedCamera> cameras) async {
    final body = await _api.post(
      '/my/cameras',
      body: {
        'device_key': deviceKey,
        'cameras': [for (final camera in cameras) camera.toJson()],
      },
    );
    return [
      for (final raw in (body['cameras'] as List? ?? const []).cast<Map<String, dynamic>>())
        ReportedCamera.fromJson(raw),
    ];
  }

  Future<Wardrobe> equip(CosmeticCategory category, String key) async =>
      Wardrobe.fromJson(
        await _api.patch(
          '/my/cosmetics',
          body: {'category': category.name, 'key': key},
        ),
      );

  /// Changes the signed-in child's own animal and returns their profile as
  /// the server saved it. Refused with a field error on `avatar` when a
  /// brother or sister already has that one.
  Future<Map<String, dynamic>> changeAvatar(String avatar) async {
    final body = await _api.patch('/my/avatar', body: {'avatar': avatar});
    return body['child'] as Map<String, dynamic>;
  }

  Future<ConsumeResult> consume(int minutes) async => ConsumeResult.fromJson(
        await _api.post('/my/consume', body: {'minutes': minutes}),
      );

  /// Sends one photo. Repeating the same client token returns the original
  /// submission instead of creating a second, so retrying is always safe.
  Future<SubmitResult> submit(OutgoingSubmission outgoing) async {
    final form = FormData.fromMap({
      'assignment_id': outgoing.assignmentId,
      'client_token': outgoing.clientToken,
      'photo': await MultipartFile.fromFile(
        outgoing.photoPath,
        filename: 'chore.jpg',
      ),
      'label': ?outgoing.label,
      'confidence': ?outgoing.confidence,
      'model_version': ?outgoing.modelVersion,
      'inference_ms': ?outgoing.inferenceMs,
    });

    final body = await _api.post('/submissions', body: form);
    return SubmitResult(
      submission: Submission.fromJson(body['submission'] as Map<String, dynamic>),
      duplicate: body['duplicate'] == true,
    );
  }

  /// Everything the phone needs to arm its alarms (BE-7), as the server
  /// sends it, for the schedule store to keep.
  Future<Map<String, dynamic>> mySchedule() => _api.get('/my/schedule');

  /// The grown-up stop (BE-10): the parent's own password, checked and
  /// recorded by the server. A wrong one is refused and changes nothing.
  Future<void> alarmOverride(String password, int assignmentId) =>
      _api.post('/alarm/override', body: {'password': password, 'assignment_id': assignmentId});

  /// Tells the parent that an alarm timed out, or that its camera was
  /// missing (DV-7, DV-12).
  Future<void> reportAlarmEvent(String kind, int assignmentId) =>
      _api.post('/my/alarm-events', body: {'kind': kind, 'assignment_id': assignmentId});

  /// The "ready for alarms" checklist and when the schedule was last copied
  /// (DV-10), so the parent's Board can say Ready or Needs setup.
  Future<void> reportDeviceStatus(Map<String, bool> checks, DateTime? lastSyncAt) =>
      _api.post('/my/device-status', body: {
        'checks': checks,
        'last_sync_at': lastSyncAt?.toUtc().toIso8601String(),
      });

  /// Sends a finished quest session (BE-2): both photos and the evidence.
  /// Nothing is credited until a grown-up approves it.
  Future<SubmitResult> sendSession(OutgoingSession outgoing) async {
    final form = FormData.fromMap({
      'assignment_id': outgoing.assignmentId,
      'client_token': outgoing.clientToken,
      'evidence': jsonEncode(outgoing.evidence),
      'before': await MultipartFile.fromFile(outgoing.beforePath, filename: 'before.jpg'),
      'after': await MultipartFile.fromFile(outgoing.afterPath, filename: 'after.jpg'),
    });

    final body = await _api.post('/quest-sessions', body: form);
    return SubmitResult(
      submission: Submission.fromJson(body['submission'] as Map<String, dynamic>),
      duplicate: body['duplicate'] == true,
    );
  }

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, dynamic> json) parse,
  ) =>
      (raw as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(parse)
          .toList();
}
