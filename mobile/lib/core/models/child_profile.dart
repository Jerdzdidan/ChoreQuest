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
  });

  factory ChildProfile.fromJson(Map<String, dynamic> json) => ChildProfile(
        id: json['id'] as int,
        name: json['name'] as String,
        avatar: json['avatar'] as String,
        birthdate: parseApiDate(json['birthdate'] as String),
        age: json['age'] as int,
        isLocked: json['is_locked'] as bool? ?? false,
      );

  final int id;
  final String name;
  final String avatar;
  final DateTime birthdate;
  final int age;

  /// Locked out after too many wrong PINs. Setting a new PIN lifts it.
  final bool isLocked;
}

/// Whole years from a birthdate to a day, counted the way the server counts.
int ageOn(DateTime birthdate, DateTime day) {
  var years = day.year - birthdate.year;
  final beforeBirthday = day.month < birthdate.month ||
      (day.month == birthdate.month && day.day < birthdate.day);
  if (beforeBirthday) years--;
  return years;
}
