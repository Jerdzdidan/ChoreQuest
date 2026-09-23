import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/family_quest.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'child_providers.dart';

/// The quest the whole household is on together, on the child's map (F3):
/// how far everyone has come, who is helping, and what each of them gets
/// when they reach it.
///
/// Shows nothing at all when there is no quest to show, rather than an empty
/// space with a heading over it.
class FamilyQuestBanner extends ConsumerWidget {
  const FamilyQuestBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ChildSession s) => s,
      _ => null,
    };
    final quests = ref.watch(myFamilyQuestsProvider).value;
    if (me == null || quests == null) return const SizedBox.shrink();

    final quest = currentFamilyQuest(quests);
    if (quest == null || quest.state == FamilyQuestState.upcoming) {
      return const SizedBox.shrink();
    }
    // A quest that ran out without being finished is not worth a place on a
    // child's map.
    if (quest.state == FamilyQuestState.missed) return const SizedBox.shrink();

    return _Banner(quest: quest, childId: me.id);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.quest, required this.childId});

  final FamilyQuest quest;
  final int childId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = QuestColors.of(context);
    final tint = quest.reached ? colors.approved : colors.xp;

    var mine = 0;
    for (final helper in quest.helpers) {
      if (helper.childId == childId) mine = helper.quests;
    }

    final line = quest.reached
        ? 'You all did it! Everyone who helped got ${formatMinutes(quest.rewardMinutesEach)}.'
        : quest.questsLeft == 1
            ? 'One more quest and everyone who helps gets ${formatMinutes(quest.rewardMinutesEach)}!'
            : '${quest.questsLeft} more quests and everyone who helps gets ${formatMinutes(quest.rewardMinutesEach)}!';

    return Semantics(
      label: [
        'Family quest: ${quest.title}.',
        '${quest.done} of ${quest.targetCount} quests done together.',
        if (mine > 0) 'You did $mine.',
        line,
      ].join(' '),
      child: ExcludeSemantics(
        child: Card(
          margin: const EdgeInsets.only(bottom: 20),
          color: tint.fill,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(quest.reached ? Icons.celebration_rounded : Icons.groups_rounded, color: tint.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        quest.title,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: tint.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${quest.done} of ${quest.targetCount} done together${mine > 0 ? ' · you did $mine' : ''}',
                  style: text.bodyMedium?.copyWith(color: tint.ink, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: quest.fraction,
                    minHeight: 12,
                    color: tint.ink,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(line, style: text.bodyMedium?.copyWith(color: tint.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
