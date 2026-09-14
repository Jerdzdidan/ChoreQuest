import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/models/api_dates.dart';
import '../../core/models/balance.dart';
import '../../core/models/child_progress.dart';
import '../../core/models/chore.dart';
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

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, dynamic> json) parse,
  ) =>
      (raw as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(parse)
          .toList();
}
