import 'api_dates.dart';

/// One entry in the age-graded chore catalogue.
class ChoreTemplate {
  const ChoreTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.category,
    required this.minAge,
    required this.maxAge,
    required this.defaultPoints,
    required this.hasVisibleEndState,
    required this.modelVerifiable,
  });

  factory ChoreTemplate.fromJson(Map<String, dynamic> json) => ChoreTemplate(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        category: json['category'] as String? ?? '',
        minAge: json['min_age'] as int,
        maxAge: json['max_age'] as int,
        defaultPoints: json['default_points'] as int,
        hasVisibleEndState: json['has_visible_end_state'] as bool? ?? false,
        modelVerifiable: json['model_verifiable'] as bool? ?? false,
      );

  final int id;
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

  /// How hard the chore is, read from the catalogue's age tiers: ages 4 and
  /// 5 tidy up, 6 and 7 take on routine upkeep, 8 and up handle water, food
  /// and the outdoors. No new data: the youngest age a chore suits is the
  /// best measure of its effort the catalogue already holds.
  QuestDifficulty get difficulty => minAge <= 5
      ? QuestDifficulty.easy
      : minAge <= 7
          ? QuestDifficulty.medium
          : QuestDifficulty.hard;

  /// Where this chore usually happens, offered first when a grown-up
  /// assigns it. Only a suggestion: the grown-up picks the place, and can
  /// change it later.
  QuestLocation get suggestedLocation => switch ((category, icon)) {
        ('kitchen', _) => QuestLocation.kitchen,
        ('bedroom', _) || (_, 'wardrobe') => QuestLocation.bedroom,
        (_, 'books') => QuestLocation.study,
        (_, 'plant' || 'laundry' || 'trash') => QuestLocation.outdoor,
        _ => QuestLocation.other,
      };
}

enum QuestDifficulty {
  easy,
  medium,
  hard;

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
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    final scheduled = json['scheduled_date'] as String?;
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
}
