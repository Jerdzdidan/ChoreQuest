import '../../core/api/api_client.dart';

class RosterChild {
  const RosterChild({required this.id, required this.name, required this.avatar});

  final int id;
  final String name;
  final String avatar;
}

class HouseholdRoster {
  const HouseholdRoster({
    required this.code,
    required this.householdName,
    required this.children,
  });

  final String code;
  final String householdName;
  final List<RosterChild> children;
}

/// The avatar picker's data: first names and faces only. The server keeps this
/// response deliberately thin, so a guessed household code learns nothing
/// beyond who to tap.
Future<HouseholdRoster> fetchHouseholdRoster(ApiClient api, String code) async {
  final normalised = code.trim().toUpperCase();
  final body = await api.get(
    '/households/${Uri.encodeComponent(normalised)}/children',
  );

  final children = (body['children'] as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .map(
        (c) => RosterChild(
          id: c['id'] as int,
          name: c['name'] as String,
          avatar: c['avatar'] as String,
        ),
      )
      .toList();

  return HouseholdRoster(
    code: normalised,
    householdName: body['household'] as String? ?? '',
    children: children,
  );
}
