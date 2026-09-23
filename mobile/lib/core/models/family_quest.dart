import 'api_dates.dart';

/// Where a shared quest stands against the household's day.
enum FamilyQuestState {
  /// Its window has not begun.
  upcoming,

  /// Running now.
  running,

  /// The window closed before the target was reached.
  missed,

  /// The target was reached.
  done;

  /// A state this version of the app does not know reads as running, so a
  /// quest is never hidden from the household.
  static FamilyQuestState parse(String? raw) => switch (raw) {
        'upcoming' => upcoming,
        'missed' => missed,
        'done' => done,
        _ => running,
      };
}

/// One child's share of a shared quest.
class FamilyQuestHelper {
  const FamilyQuestHelper({required this.childId, required this.name, required this.quests});

  final int childId;
  final String name;
  final int quests;
}

/// A quest the whole household works on together (F1-F3), as the server
/// counts it: the target, how many approved quests count towards it so far,
/// who helped, and what each of them gets when it is reached.
class FamilyQuest {
  const FamilyQuest({
    required this.id,
    required this.title,
    required this.targetCount,
    required this.rewardMinutesEach,
    required this.startsAt,
    required this.endsAt,
    required this.done,
    required this.reached,
    required this.rewardedAt,
    required this.state,
    required this.helpers,
  });

  factory FamilyQuest.fromJson(Map<String, dynamic> json) => FamilyQuest(
        id: json['id'] as int,
        title: json['title'] as String,
        targetCount: json['target_count'] as int,
        rewardMinutesEach: json['reward_minutes_each'] as int,
        startsAt: parseApiDate(json['starts_at'] as String),
        endsAt: parseApiDate(json['ends_at'] as String),
        done: json['done'] as int? ?? 0,
        reached: json['reached'] as bool? ?? false,
        rewardedAt: json['rewarded_at'] == null ? null : DateTime.parse(json['rewarded_at'] as String),
        state: FamilyQuestState.parse(json['state'] as String?),
        helpers: [
          for (final raw in (json['helpers'] as List? ?? const []).cast<Map<String, dynamic>>())
            FamilyQuestHelper(
              childId: raw['child_id'] as int,
              name: raw['name'] as String? ?? 'A child',
              quests: raw['quests'] as int? ?? 0,
            ),
        ],
      );

  final int id;
  final String title;
  final int targetCount;

  /// What each child who helped receives when the target is reached.
  final int rewardMinutesEach;
  final DateTime startsAt;
  final DateTime endsAt;

  /// Approved quests counted towards it so far.
  final int done;
  final bool reached;

  /// When the minutes went out, or null while they have not.
  final DateTime? rewardedAt;
  final FamilyQuestState state;
  final List<FamilyQuestHelper> helpers;

  /// How full the bar is, from 0 to 1.
  double get fraction => targetCount <= 0 ? 1 : (done / targetCount).clamp(0.0, 1.0).toDouble();

  int get questsLeft => targetCount - done < 0 ? 0 : targetCount - done;
}

/// The one quest a household is shown: the one running, else the next to
/// start, else the latest there was. Null when there has never been one.
FamilyQuest? currentFamilyQuest(List<FamilyQuest> quests) {
  for (final state in [FamilyQuestState.running, FamilyQuestState.upcoming]) {
    for (final quest in quests) {
      if (quest.state == state) return quest;
    }
  }
  return quests.isEmpty ? null : quests.first;
}
