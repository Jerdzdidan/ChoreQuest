import 'api_dates.dart';

enum SubmissionStatus {
  approved,
  rejected,
  pending;

  /// Anything unrecognised is treated as still waiting, which is the safe
  /// reading: it neither credits screen time nor tells a child they failed.
  static SubmissionStatus parse(String? raw) => switch (raw) {
        'approved' => approved,
        'rejected' => rejected,
        _ => pending,
      };
}

/// How a quest was finished: one photo checked automatically before Phase 4,
/// or a live quest session, watched by the movement model or checked by the
/// parent alone.
enum SessionMode {
  legacyPhoto,
  motion,
  manual;

  static SessionMode parse(String? raw) => switch (raw) {
        'lstm' => motion,
        'manual' => manual,
        _ => legacyPhoto,
      };
}

/// What a quest session's phone saw (LS-8), as the parent's review shows it.
/// Every figure may be missing: a manual session has no model figures, and a
/// phone may not measure everything.
class SessionEvidence {
  const SessionEvidence(this._json);

  factory SessionEvidence.fromJson(Map<String, dynamic> json) => SessionEvidence(json);

  final Map<String, dynamic> _json;

  int? _int(String key) => (_json[key] as num?)?.toInt();
  double? _double(String key) => (_json[key] as num?)?.toDouble();
  bool _flag(String key) => _json[key] == true;

  int? get sessionSeconds => _int('session_seconds');
  int? get activeSeconds => _int('active_seconds');
  double? get meanProbability => _double('mean_probability');
  double? get sceneChange => _double('scene_change');
  bool? get sceneFits => _json['scene_fits'] as bool?;

  /// phone_back, or phone_front on a phone with no back camera; external or
  /// network on sessions from before Phase 5.
  String? get camera => _json['camera'] as String?;

  /// Before Phase 5: the child flipped the camera.
  bool get cameraFlipped => _flag('camera_flipped');

  /// Before Phase 5: the scheduled third-party camera was missing.
  bool get cameraFallback => _flag('camera_fallback');

  /// The movement model could not run, so the session went manual.
  bool get modelUnavailable => _flag('model_unavailable');

  /// The child started without the phone on a strap (CAM-3).
  bool get noStrap => _flag('no_strap');

  /// The phone has no back camera.
  bool get noBackCamera => _flag('no_back_camera');
}

/// What the confidence thresholds decided when the photo arrived.
enum Routing {
  autoApproved,
  pendingReview,
  autoRejected;

  static Routing parse(String? raw) => switch (raw) {
        'auto_approved' => autoApproved,
        'auto_rejected' => autoRejected,
        _ => pendingReview,
      };
}

/// One finished quest a child sent: a single photo from before Phase 4, or a
/// quest session's Before and After photos and evidence, with what a parent
/// decided kept beside what the phone or the photo check reported.
class Submission {
  const Submission({
    required this.id,
    required this.childId,
    required this.assignmentId,
    required this.choreName,
    required this.childName,
    required this.modelLabel,
    required this.modelConfidence,
    required this.modelVersion,
    required this.inferenceMs,
    required this.routing,
    required this.parentDecision,
    required this.parentDecidedAt,
    required this.wasOverridden,
    required this.status,
    required this.forDate,
    required this.photoUrl,
    required this.submittedAt,
    this.mode = SessionMode.legacyPhoto,
    this.beforePhotoUrl,
    this.evidence,
    this.activeSeconds,
    this.sessionStartedAt,
    this.sessionDoneAt,
  });

  factory Submission.fromJson(Map<String, dynamic> json) {
    final decision = json['parent_decision'] as String?;
    final decidedAt = json['parent_decided_at'] as String?;
    final evidence = json['evidence'];
    final started = json['session_started_at'] as String?;
    final done = json['session_done_at'] as String?;
    return Submission(
      id: json['id'] as int,
      childId: json['child_id'] as int,
      assignmentId: json['assignment_id'] as int,
      // Only present when the server loaded the chore alongside, which the
      // intake endpoint does for automatic approvals alone.
      choreName: json['chore'] as String?,
      childName: json['child_name'] as String?,
      modelLabel: json['model_label'] as String?,
      modelConfidence: (json['model_confidence'] as num?)?.toDouble(),
      modelVersion: json['model_version'] as String?,
      inferenceMs: json['inference_ms'] as int?,
      routing: Routing.parse(json['routing'] as String?),
      parentDecision:
          decision == null ? null : SubmissionStatus.parse(decision),
      parentDecidedAt: decidedAt == null ? null : DateTime.parse(decidedAt),
      wasOverridden: json['was_overridden'] as bool? ?? false,
      status: SubmissionStatus.parse(json['status'] as String?),
      forDate: parseApiDate(json['for_date'] as String),
      photoUrl: json['photo_url'] as String,
      submittedAt: DateTime.parse(json['submitted_at'] as String),
      mode: SessionMode.parse(json['verification_mode'] as String?),
      beforePhotoUrl: json['before_photo_url'] as String?,
      evidence: evidence is Map<String, dynamic> ? SessionEvidence.fromJson(evidence) : null,
      activeSeconds: json['active_seconds'] as int?,
      sessionStartedAt: started == null ? null : DateTime.parse(started),
      sessionDoneAt: done == null ? null : DateTime.parse(done),
    );
  }

  final int id;
  final int childId;
  final int assignmentId;
  final String? choreName;
  final String? childName;
  final String? modelLabel;
  final double? modelConfidence;
  final String? modelVersion;
  final int? inferenceMs;
  final Routing routing;

  /// Null until a parent has looked at it.
  final SubmissionStatus? parentDecision;
  final DateTime? parentDecidedAt;
  final bool wasOverridden;
  final SubmissionStatus status;
  final DateTime forDate;
  /// The After photo of a session, or the one photo of an older quest.
  final String photoUrl;
  final DateTime submittedAt;

  final SessionMode mode;
  final String? beforePhotoUrl;
  final SessionEvidence? evidence;

  /// Seconds of movement that matched the chore, for a motion-checked one.
  final int? activeSeconds;
  final DateTime? sessionStartedAt;
  final DateTime? sessionDoneAt;

  /// A live quest session rather than one photo.
  bool get isSession => mode != SessionMode.legacyPhoto;

  /// For an older single-photo quest: how sure the automatic photo check was
  /// that the chore is done, on a single axis, the way the server routed it.
  /// Null when it did not run.
  double? get confidenceDone {
    final confidence = modelConfidence;
    if (confidence == null || modelLabel == null) return null;
    return modelLabel == 'done' ? confidence : 1 - confidence;
  }
}
