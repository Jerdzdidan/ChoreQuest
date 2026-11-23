import '../../core/api/api_client.dart';
import '../../core/models/allocation_rule.dart';
import '../../core/models/api_dates.dart';
import '../../core/models/child_activity.dart';
import '../../core/models/child_profile.dart';
import '../../core/models/chore.dart';
import '../../core/models/family_quest.dart';
import '../../core/models/parent_notification.dart';
import '../../core/models/screen_time_report.dart';
import '../../core/models/submission.dart';

/// Everything the parent's screens ask of the server, typed.
///
/// Free of Flutter imports on purpose, so it runs under plain Dart and can be
/// driven against the real API without an emulator.
class ParentApi {
  const ParentApi(this._api);

  final ApiClient _api;

  Future<List<ChildProfile>> children() async {
    final body = await _api.get('/children');
    return _list(body['children'], ChildProfile.fromJson);
  }

  Future<ChildProfile> addChild({
    required String name,
    required String avatar,
    required DateTime birthdate,
    required String pin,
  }) async {
    final body = await _api.post(
      '/children',
      body: {
        'name': name,
        'avatar': avatar,
        'birthdate': isoDate(birthdate),
        'pin': pin,
      },
    );
    return ChildProfile.fromJson(body['child'] as Map<String, dynamic>);
  }

  /// Sends only what changed. A new PIN is also what lifts a lockout.
  Future<ChildProfile> updateChild(
    int childId, {
    String? name,
    String? avatar,
    DateTime? birthdate,
    String? pin,
  }) async {
    final body = await _api.patch(
      '/children/$childId',
      body: {
        'name': ?name,
        'avatar': ?avatar,
        if (birthdate != null) 'birthdate': isoDate(birthdate),
        'pin': ?pin,
      },
    );
    return ChildProfile.fromJson(body['child'] as Map<String, dynamic>);
  }

  Future<void> removeChild(int childId) => _api.delete('/children/$childId');

  /// The whole catalogue, every age: the Quests tab (PQ1). Its categories
  /// come with it, Custom chore last.
  Future<ChoreCatalogue> catalogue() async =>
      ChoreCatalogue.fromJson(await _api.get('/chores'));

  /// Only the chores suited to this child's age, with the categories.
  Future<ChoreCatalogue> catalogueFor(int childId) async =>
      ChoreCatalogue.fromJson(await _api.get('/chores', query: {'child_id': childId}));

  Future<List<Assignment>> assignments(int childId) async {
    final body = await _api.get('/assignments', query: {'child_id': childId});
    return _list(body['assignments'], Assignment.fromJson);
  }

  Future<Assignment> assign({
    required int childId,
    required int templateId,
    required int points,
    QuestSchedule schedule = const QuestSchedule(),
    QuestLocation location = QuestLocation.other,
  }) async {
    final body = await _api.post(
      '/assignments',
      body: {
        'child_id': childId,
        'chore_template_id': templateId,
        'points': points,
        ...schedule.wire,
        'location': location.name,
      },
    );
    return Assignment.fromJson(body['assignment'] as Map<String, dynamic>);
  }

  /// Changes an assignment. A [schedule], when given, replaces the whole
  /// schedule: the alarm, the repeat and its weekdays, the ringtone and the
  /// camera (PS-7).
  Future<Assignment> updateAssignment(
    int assignmentId, {
    int? points,
    bool? isActive,
    QuestLocation? location,
    QuestSchedule? schedule,
  }) async {
    final body = await _api.patch(
      '/assignments/$assignmentId',
      body: {
        'points': ?points,
        'is_active': ?isActive,
        'location': ?location?.name,
        ...?schedule?.wire,
      },
    );
    return Assignment.fromJson(body['assignment'] as Map<String, dynamic>);
  }

  Future<void> removeAssignment(int assignmentId) =>
      _api.delete('/assignments/$assignmentId');

  Future<AllocationRule> rule(int childId) async {
    final body = await _api.get('/children/$childId/rule');
    return AllocationRule.fromJson(body['rule'] as Map<String, dynamic>);
  }

  Future<AllocationRule> updateRule(AllocationRule rule) async {
    final body = await _api.patch(
      '/children/${rule.childId}/rule',
      body: rule.toJson(),
    );
    return AllocationRule.fromJson(body['rule'] as Map<String, dynamic>);
  }

  /// Changes one child's caps and nothing else (BD1): the exchange rate and
  /// both thresholds stay as they are, and the server still checks that the
  /// weekly cap is not below the daily one.
  Future<AllocationRule> setCaps(int childId, {int? dailyCapMinutes, int? weeklyCapMinutes}) async {
    final body = await _api.patch('/children/$childId/rule', body: {
      'daily_cap_minutes': ?dailyCapMinutes,
      'weekly_cap_minutes': ?weeklyCapMinutes,
    });
    return AllocationRule.fromJson(body['rule'] as Map<String, dynamic>);
  }

  /// The household's shared quests, the newest window first (F2).
  Future<List<FamilyQuest>> familyQuests() async {
    final body = await _api.get('/family-quests');
    return _list(body['family_quests'], FamilyQuest.fromJson);
  }

  /// Sets up a shared quest. Dates are household days, as Y-m-d.
  Future<FamilyQuest> createFamilyQuest({
    required String title,
    required int targetCount,
    required int rewardMinutesEach,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final body = await _api.post('/family-quests', body: {
      'title': title,
      'target_count': targetCount,
      'reward_minutes_each': rewardMinutesEach,
      'starts_at': isoDate(startsAt),
      'ends_at': isoDate(endsAt),
    });
    return FamilyQuest.fromJson(body['family_quest'] as Map<String, dynamic>);
  }

  /// Calls a shared quest off. Minutes already paid stay paid.
  Future<void> deleteFamilyQuest(int questId) => _api.delete('/family-quests/$questId');

  /// Photos with no decision yet, newest first. With [everything], the latest
  /// 100 of every kind, including those the checker decided.
  Future<List<Submission>> reviews({bool everything = false}) async {
    final body = await _api.get(
      '/reviews',
      query: everything ? {'scope': 'all'} : null,
    );
    return _list(body['submissions'], Submission.fromJson);
  }

  /// A parent's answer to one photo. It may confirm or overturn what the
  /// checker decided, and may be changed later, except that a photo whose
  /// screen time has been taken back once cannot be approved again: the
  /// server answers that with 409.
  Future<Submission> decide(int submissionId, {required bool approved}) async {
    final body = await _api.post(
      '/submissions/$submissionId/decide',
      body: {'decision': approved ? 'approved' : 'rejected'},
    );
    return Submission.fromJson(body['submission'] as Map<String, dynamic>);
  }

  /// Changes the parent's own account. Only what is passed changes; a new
  /// password needs the current one, which the server checks. Returns the
  /// account as saved, shaped like the `parent` in a sign-in response.
  Future<Map<String, dynamic>> updateAccount({
    String? name,
    String? email,
    String? avatar,
    String? password,
    String? currentPassword,
  }) async {
    final body = await _api.patch(
      '/me',
      body: {
        'name': ?name,
        'email': ?email,
        'avatar': ?avatar,
        'password': ?password,
        'password_confirmation': ?password,
        'current_password': ?currentPassword,
      },
    );
    return body['parent'] as Map<String, dynamic>;
  }

  /// The latest 100 photos across the household as notifications, and how
  /// many arrived since the list was last opened.
  Future<NotificationFeed> notifications() async =>
      NotificationFeed.fromJson(await _api.get('/notifications'));

  /// The parent has opened the list: nothing so far is unread any more.
  Future<void> markNotificationsSeen() => _api.post('/notifications/seen');

  /// One child's screen time: balance, limits, totals, and the latest 200
  /// ledger rows.
  /// One child's figures for the Activity tab (ACT1), all in one answer.
  Future<ChildActivity> activity(int childId) async =>
      ChildActivity.fromJson(await _api.get('/children/$childId/activity'));

  Future<ScreenTimeReport> report(int childId) async =>
      ScreenTimeReport.fromJson(await _api.get('/children/$childId/report'));

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, dynamic> json) parse,
  ) =>
      (raw as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(parse)
          .toList();
}
