import 'api_dates.dart';

/// A child in the signed-in parent's household, as the parent sees them.
class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.birthdate,
    required this.age,
    required this.isLocked,
    this.device = PhoneReadiness.unknown,
  });

  factory ChildProfile.fromJson(Map<String, dynamic> json) => ChildProfile(
        id: json['id'] as int,
        name: json['name'] as String,
        avatar: json['avatar'] as String,
        birthdate: parseApiDate(json['birthdate'] as String),
        age: json['age'] as int,
        isLocked: json['is_locked'] as bool? ?? false,
        device: PhoneReadiness.parse((json['device'] as Map<String, dynamic>?)?['state'] as String?),
      );

  final int id;
  final String name;
  final String avatar;
  final DateTime birthdate;
  final int age;

  /// Locked out after too many wrong PINs. Setting a new PIN lifts it.
  final bool isLocked;

  /// Whether the child's phone is ready to ring (BE-9).
  final PhoneReadiness device;
}

/// What the child's phone last said about its "ready for alarms" checklist.
enum PhoneReadiness {
  ready,
  needsSetup,

  /// The phone has never reported.
  unknown;

  static PhoneReadiness parse(String? raw) => switch (raw) {
        'ready' => ready,
        'needs_setup' => needsSetup,
        _ => unknown,
      };
}

/// Whole years from a birthdate to a day, counted the way the server counts.
int ageOn(DateTime birthdate, DateTime day) {
  var years = day.year - birthdate.year;
  final beforeBirthday = day.month < birthdate.month ||
      (day.month == birthdate.month && day.day < birthdate.day);
  if (beforeBirthday) years--;
  return years;
}
