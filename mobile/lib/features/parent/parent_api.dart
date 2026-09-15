import '../../core/api/api_client.dart';
import '../../core/models/allocation_rule.dart';
import '../../core/models/api_dates.dart';
import '../../core/models/child_profile.dart';
import '../../core/models/chore.dart';
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

  /// Only the chores suited to this child's age.
  Future<List<ChoreTemplate>> catalogueFor(int childId) async {
    final body = await _api.get('/chores', query: {'child_id': childId});
    return _list(body['chores'], ChoreTemplate.fromJson);
  }

  Future<List<Assignment>> assignments(int childId) async {
    final body = await _api.get('/assignments', query: {'child_id': childId});
    return _list(body['assignments'], Assignment.fromJson);
  }

  Future<Assignment> assign({
    required int childId,
    required int templateId,
    required int points,
    ClockTime? dueTime,
    Recurrence recurrence = Recurrence.daily,
    DateTime? scheduledDate,
    QuestLocation location = QuestLocation.other,
  }) async {
    final body = await _api.post(
      '/assignments',
      body: {
        'child_id': childId,
        'chore_template_id': templateId,
        'points': points,
        'due_time': dueTime?.wire,
        'recurrence': recurrence.name,
        if (recurrence == Recurrence.once && scheduledDate != null)
          'scheduled_date': isoDate(scheduledDate),
        'location': location.name,
      },
    );
    return Assignment.fromJson(body['assignment'] as Map<String, dynamic>);
  }

  Future<Assignment> updateAssignment(
    int assignmentId, {
    int? points,
    ClockTime? dueTime,
    bool clearDueTime = false,
    bool? isActive,
    QuestLocation? location,
  }) async {
    final body = await _api.patch(
      '/assignments/$assignmentId',
      body: {
        'points': ?points,
        if (dueTime != null)
          'due_time': dueTime.wire
        else if (clearDueTime)
          'due_time': null,
        'is_active': ?isActive,
        'location': ?location?.name,
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

  /// One child's screen time: balance, limits, totals, and the latest 200
  /// ledger rows.
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
