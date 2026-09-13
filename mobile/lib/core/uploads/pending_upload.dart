/// A photo waiting to reach the server, as it is written to disk.
class PendingUpload {
  const PendingUpload({
    required this.clientToken,
    required this.childId,
    required this.assignmentId,
    required this.choreName,
    required this.photoPath,
    required this.createdAt,
    this.label,
    this.confidence,
    this.modelVersion,
    this.inferenceMs,
    this.attempts = 0,
    this.lastError,
  });

  factory PendingUpload.fromJson(Map<String, dynamic> json) => PendingUpload(
        clientToken: json['client_token'] as String,
        childId: json['child_id'] as int,
        assignmentId: json['assignment_id'] as int,
        choreName: json['chore_name'] as String? ?? '',
        photoPath: json['photo_path'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        label: json['label'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
        modelVersion: json['model_version'] as String?,
        inferenceMs: json['inference_ms'] as int?,
        attempts: json['attempts'] as int? ?? 0,
        lastError: json['last_error'] as String?,
      );

  /// Sent with every attempt, so the server can recognise a repeat.
  final String clientToken;

  /// The child it belongs to. On a shared phone, a brother's or sister's
  /// upload waits for them to sign in; it never goes up under another token.
  final int childId;
  final int assignmentId;
  final String choreName;

  /// The queue's own copy of the photo, not the camera's cache file.
  final String photoPath;
  final DateTime createdAt;
  final String? label;
  final double? confidence;
  final String? modelVersion;
  final int? inferenceMs;
  final int attempts;
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'client_token': clientToken,
        'child_id': childId,
        'assignment_id': assignmentId,
        'chore_name': choreName,
        'photo_path': photoPath,
        'created_at': createdAt.toIso8601String(),
        'label': label,
        'confidence': confidence,
        'model_version': modelVersion,
        'inference_ms': inferenceMs,
        'attempts': attempts,
        'last_error': lastError,
      };

  PendingUpload failedAgain(String message) => PendingUpload(
        clientToken: clientToken,
        childId: childId,
        assignmentId: assignmentId,
        choreName: choreName,
        photoPath: photoPath,
        createdAt: createdAt,
        label: label,
        confidence: confidence,
        modelVersion: modelVersion,
        inferenceMs: inferenceMs,
        attempts: attempts + 1,
        lastError: message,
      );
}
