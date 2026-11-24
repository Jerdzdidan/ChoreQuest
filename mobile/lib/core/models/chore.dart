import 'api_dates.dart';

/// One entry in the age-graded chore catalogue.
class ChoreTemplate {
  const ChoreTemplate({
    required this.id,
    this.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    required this.minAge,
    required this.maxAge,
    required this.defaultPoints,
    required this.hasVisibleEndState,
    required this.modelVerifiable,
    this.difficulty = QuestDifficulty.easy,
    this.location = QuestLocation.other,
    this.verificationMode = VerificationMode.manual,
    this.modelClass,
    this.minActiveSeconds,
    this.isCustom = false,
  });

  factory ChoreTemplate.fromJson(Map<String, dynamic> json) => ChoreTemplate(
        id: json['id'] as int,
        key: json['key'] as String?,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        category: json['category'] as String? ?? '',
        minAge: json['min_age'] as int,
        maxAge: json['max_age'] as int,
        defaultPoints: json['default_points'] as int,
        hasVisibleEndState: json['has_visible_end_state'] as bool? ?? false,
        modelVerifiable: json['model_verifiable'] as bool? ?? false,
        difficulty: QuestDifficulty.parse(json['difficulty'] as String?),
        location: QuestLocation.parse(json['location'] as String?),
        verificationMode: VerificationMode.parse(json['verification_mode'] as String?),
        modelClass: json['model_class'] as int?,
        minActiveSeconds: json['min_active_seconds'] as int?,
        isCustom: json['is_custom'] as bool? ?? false,
      );

  final int id;

  /// The chore's key in ml/chore_manifest.json; null for a custom chore.
  final String? key;
  final String name;
  final String description;
  final String icon;
  final String category;
  final int minAge;
  final int maxAge;
  final int defaultPoints;
  final bool hasVisibleEndState;

  /// Whether the photo checker can judge this chore at all. Only the three
  /// trained classes can; every other chore always goes to a parent.
  final bool modelVerifiable;

  /// How hard the chore is, as the catalogue says. Its XP follows from this
  /// (difficulty_xp.dart).
  final QuestDifficulty difficulty;

  /// Where in a home this chore usually happens, as the catalogue says.
  /// Offered first when a grown-up assigns it; the assignment's own
  /// location is what the quest map uses.
  final QuestLocation location;

  /// How the quest session checks it (Phase 4).
  final VerificationMode verificationMode;

  /// The movement model's class for a motion-checked chore.
  final int? modelClass;

  /// Seconds of matching movement before Done appears, unless the model
  /// config names its own.
  final int? minActiveSeconds;

  /// A chore the parent made up. Only that parent sees it, and only the
  /// parent checks it.
  final bool isCustom;
}

/// How a chore is checked in a quest session.
enum VerificationMode {
  /// The movement model watches; Done appears after enough movement that
  /// looks like this chore.
  motion,

  /// No model: the parent checks the Before and After photos.
  manual;

  /// Anything this version does not know reads as [manual], the side that
  /// never lets a model decide.
  static VerificationMode parse(String? raw) => raw == 'lstm' ? motion : manual;

  String get label => switch (this) {
        motion => 'Motion-checked',
        manual => 'Manual check',
      };
}

/// A group of chores a parent picks from first: "Kitchen & dishes", and
/// "Custom chore" last. The list comes from the server.
class ChoreCategory {
  const ChoreCategory({required this.key, required this.name});

  factory ChoreCategory.fromJson(Map<String, dynamic> json) =>
      ChoreCategory(key: json['key'] as String, name: json['name'] as String);

  /// The key of the parent's own chores.
  static const custom = 'custom';

  final String key;
  final String name;

  bool get isCustom => key == custom;
}

/// The catalogue as the server sends it: the categories, in order, and the
/// chores.
class ChoreCatalogue {
  const ChoreCatalogue({required this.categories, required this.chores});

  factory ChoreCatalogue.fromJson(Map<String, dynamic> json) => ChoreCatalogue(
        categories: [
          for (final raw in (json['categories'] as List? ?? const []).cast<Map<String, dynamic>>())
            ChoreCategory.fromJson(raw),
        ],
        chores: [
          for (final raw in (json['chores'] as List? ?? const []).cast<Map<String, dynamic>>())
            ChoreTemplate.fromJson(raw),
        ],
      );

  final List<ChoreCategory> categories;
  final List<ChoreTemplate> chores;
}

enum QuestDifficulty {
  easy,
  medium,
  hard;

  /// A tier this version of the app does not know reads as [easy], the
  /// smallest reward, rather than failing to show the quest.
  static QuestDifficulty parse(String? raw) {
    for (final difficulty in values) {
      if (difficulty.name == raw) return difficulty;
    }
    return easy;
  }

  String get label => switch (this) {
        easy => 'Easy',
        medium => 'Medium',
        hard => 'Hard',
      };
}

/// Where in the home a quest happens: the places on a child's quest map.
enum QuestLocation {
  kitchen,
  bedroom,
  study,
  outdoor,
  other;

  /// A place this version of the app does not know reads as [other], so a
  /// quest is never lost from the map.
  static QuestLocation parse(String? raw) {
    for (final location in values) {
      if (location.name == raw) return location;
    }
    return other;
  }

  String get label => switch (this) {
        kitchen => 'Kitchen',
        bedroom => 'Bedroom',
        study => 'Study table',
        outdoor => 'Outdoor area',
        other => 'Other',
      };
}

enum Recurrence {
  daily,
  once;

  static Recurrence parse(String? raw) => raw == 'once' ? once : daily;
}

/// When a quest rings on the child's phone (PS-7). Every quest is watched
/// through the phone's back camera, on a strap (CAM-3).
class QuestSchedule {
  const QuestSchedule({
    this.recurrence = Recurrence.daily,
    this.scheduledDate,
    this.daysOfWeek,
    this.alarmTime,
    this.ringtoneKey = defaultRingtone,
    this.alarmEnabled = true,
  });

  static const defaultRingtone = 'classic';

  final Recurrence recurrence;

  /// The day of a one-time quest.
  final DateTime? scheduledDate;

  /// The weekdays a daily quest repeats on, as [DateTime.weekday] numbers
  /// (1 Monday to 7 Sunday). Null means every day, which is what every
  /// quest set before weekdays existed has.
  final List<int>? daysOfWeek;

  /// When the alarm rings: the old "Finish by" time.
  final ClockTime? alarmTime;
  final String ringtoneKey;
  final bool alarmEnabled;

  /// Whether a daily quest repeats on [weekday] (1 Monday to 7 Sunday).
  bool repeatsOn(int weekday) => daysOfWeek == null || daysOfWeek!.contains(weekday);

  /// The fields as the API takes them. The camera is not among them: the
  /// server sets the phone's on every quest (CAM-1).
  Map<String, Object?> get wire => {
        'recurrence': recurrence.name,
        'due_time': alarmTime?.wire,
        'scheduled_date': recurrence == Recurrence.once && scheduledDate != null ? isoDate(scheduledDate!) : null,
        'days_of_week': recurrence == Recurrence.daily ? daysOfWeek : null,
        'ringtone_key': ringtoneKey,
        'alarm_enabled': alarmEnabled,
      };
}

/// A chore given to one child, with the points and schedule the parent chose.
class Assignment {
  const Assignment({
    required this.id,
    required this.childId,
    required this.points,
    required this.dueTime,
    required this.recurrence,
    required this.scheduledDate,
    required this.isActive,
    required this.chore,
    this.location = QuestLocation.other,
    this.daysOfWeek,
    this.ringtoneKey = QuestSchedule.defaultRingtone,
    this.alarmEnabled = true,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    final scheduled = json['scheduled_date'] as String?;
    final days = json['days_of_week'] as List?;
    return Assignment(
      id: json['id'] as int,
      childId: json['child_id'] as int,
      points: json['points'] as int,
      dueTime: ClockTime.tryParse(json['due_time'] as String?),
      recurrence: Recurrence.parse(json['recurrence'] as String?),
      scheduledDate: scheduled == null ? null : parseApiDate(scheduled),
      isActive: json['is_active'] as bool? ?? true,
      chore: ChoreTemplate.fromJson(json['chore'] as Map<String, dynamic>),
      location: QuestLocation.parse(json['location'] as String?),
      daysOfWeek: days == null ? null : [for (final day in days) day as int],
      ringtoneKey: json['ringtone_key'] as String? ?? QuestSchedule.defaultRingtone,
      alarmEnabled: json['alarm_enabled'] as bool? ?? true,
    );
  }

  final int id;
  final int childId;
  final int points;
  final ClockTime? dueTime;
  final Recurrence recurrence;
  final DateTime? scheduledDate;
  final bool isActive;
  final ChoreTemplate chore;

  /// Where in the home it happens, as the parent set it.
  final QuestLocation location;

  /// The weekdays a daily quest repeats on; null is every day.
  final List<int>? daysOfWeek;
  final String ringtoneKey;
  final bool alarmEnabled;

  /// The schedule as one value, for editing it (PS-7).
  QuestSchedule get schedule => QuestSchedule(
        recurrence: recurrence,
        scheduledDate: scheduledDate,
        daysOfWeek: daysOfWeek,
        alarmTime: dueTime,
        ringtoneKey: ringtoneKey,
        alarmEnabled: alarmEnabled,
      );
}
