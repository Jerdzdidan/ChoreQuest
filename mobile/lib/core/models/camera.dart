/// What sort of camera a phone can see (BE-8, DV-8).
enum CameraKind {
  /// The phone's own front or back camera.
  phone,

  /// A USB camera the camera plugin lists as external.
  external,

  /// A CCTV or IP camera added by its address.
  network;

  /// Anything this version does not know reads as [network], a camera the
  /// phone does not own, so it is never mistaken for the phone's.
  static CameraKind parse(String? raw) => switch (raw) {
        'phone' => phone,
        'external' => external,
        _ => network,
      };

  bool get isThirdParty => this != phone;
}

/// One camera as a child's phone reports it, and as the parent's phone reads
/// it back.
class ReportedCamera {
  const ReportedCamera({
    required this.key,
    required this.kind,
    required this.label,
    required this.connected,
    this.lastSeenAt,
  });

  factory ReportedCamera.fromJson(Map<String, dynamic> json) {
    final seen = json['last_seen_at'] as String?;
    return ReportedCamera(
      key: json['key'] as String,
      kind: CameraKind.parse(json['kind'] as String?),
      label: json['label'] as String? ?? 'Camera',
      connected: json['connected'] as bool? ?? false,
      lastSeenAt: seen == null ? null : DateTime.parse(seen),
    );
  }

  /// Stable on the phone that reported it; what an assignment's
  /// camera_device_id names.
  final String key;
  final CameraKind kind;

  /// What the parent sees, such as "Kitchen CCTV".
  final String label;
  final bool connected;
  final DateTime? lastSeenAt;

  Map<String, Object?> toJson() => {
        'key': key,
        'kind': kind.name,
        'label': label,
        'connected': connected,
      };
}
