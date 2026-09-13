/// Who is signed in on this device.
///
/// Sealed, so anything that switches on a session must handle all three cases.
/// The compiler, rather than a careful reviewer, is what guarantees a child's
/// session can never be treated as a parent's.
sealed class Session {
  const Session();

  String? get token;

  Map<String, dynamic> toJson();

  static Session fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'parent' => ParentSession.fromJson(json),
      'child' => ChildSession.fromJson(json),
      _ => const SignedOut(),
    };
  }
}

final class SignedOut extends Session {
  const SignedOut();

  @override
  String? get token => null;

  @override
  Map<String, dynamic> toJson() => {'type': 'signed_out'};
}

final class ParentSession extends Session {
  const ParentSession({
    required this.token,
    required this.id,
    required this.name,
    required this.email,
    required this.householdCode,
  });

  /// From the body of POST /login or POST /register.
  factory ParentSession.fromAuthResponse(Map<String, dynamic> body) {
    final parent = body['parent'] as Map<String, dynamic>;
    return ParentSession(
      token: body['token'] as String,
      id: parent['id'] as int,
      name: parent['name'] as String,
      email: parent['email'] as String,
      householdCode: parent['household_code'] as String,
    );
  }

  factory ParentSession.fromJson(Map<String, dynamic> json) => ParentSession(
        token: json['token'] as String,
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        householdCode: json['household_code'] as String,
      );

  @override
  final String token;
  final int id;
  final String name;
  final String email;

  /// Read aloud once to pair a child's device with this household.
  final String householdCode;

  /// Refreshes profile fields from GET /me, keeping the same token.
  ParentSession withProfile(Map<String, dynamic> parent) => ParentSession(
        token: token,
        id: parent['id'] as int,
        name: parent['name'] as String,
        email: parent['email'] as String,
        householdCode: parent['household_code'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'parent',
        'token': token,
        'id': id,
        'name': name,
        'email': email,
        'household_code': householdCode,
      };
}

final class ChildSession extends Session {
  const ChildSession({
    required this.token,
    required this.id,
    required this.name,
    required this.avatar,
    required this.age,
    required this.householdCode,
  });

  /// From the body of POST /child/login.
  factory ChildSession.fromAuthResponse(
    Map<String, dynamic> body, {
    required String householdCode,
  }) {
    final child = body['child'] as Map<String, dynamic>;
    return ChildSession(
      token: body['token'] as String,
      id: child['id'] as int,
      name: child['name'] as String,
      avatar: child['avatar'] as String,
      age: child['age'] as int,
      householdCode: householdCode,
    );
  }

  factory ChildSession.fromJson(Map<String, dynamic> json) => ChildSession(
        token: json['token'] as String,
        id: json['id'] as int,
        name: json['name'] as String,
        avatar: json['avatar'] as String,
        age: json['age'] as int,
        householdCode: json['household_code'] as String,
      );

  @override
  final String token;
  final int id;
  final String name;
  final String avatar;
  final int age;
  final String householdCode;

  ChildSession withProfile(Map<String, dynamic> child) => ChildSession(
        token: token,
        id: child['id'] as int,
        name: child['name'] as String,
        avatar: child['avatar'] as String,
        age: child['age'] as int,
        householdCode: householdCode,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'child',
        'token': token,
        'id': id,
        'name': name,
        'avatar': avatar,
        'age': age,
        'household_code': householdCode,
      };
}
