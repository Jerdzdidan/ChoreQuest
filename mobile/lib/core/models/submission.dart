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

/// One photograph a child sent: what the checker made of it, and what a
/// parent decided, kept side by side.
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
  });

  factory Submission.fromJson(Map<String, dynamic> json) {
    final decision = json['parent_decision'] as String?;
    final decidedAt = json['parent_decided_at'] as String?;
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
  final String photoUrl;
  final DateTime submittedAt;

  /// How sure the checker was that the chore is done, on a single axis, the
  /// same way the server routes it. Null when no checker ran.
  double? get confidenceDone {
    final confidence = modelConfidence;
    if (confidence == null || modelLabel == null) return null;
    return modelLabel == 'done' ? confidence : 1 - confidence;
  }
}
