import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/family_quest.dart';
import '../../shared/async_view.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import 'family_quest_form_screen.dart';
import 'parent_providers.dart';

/// The household's shared quest on the Board (F2): how far everyone has come
/// together, who has helped, and what each of them gets when the target is
/// reached. With none set up, an invitation to start one.
class FamilyQuestCard extends ConsumerWidget {
  const FamilyQuestCard({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final made = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FamilyQuestFormScreen()),
    );
    if (made == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The family quest has started.')),
      );
    }
  }

  Future<void> _callOff(BuildContext context, WidgetRef ref, FamilyQuest quest) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Call off "${quest.title}"?'),
        content: const Text(
          'The shared progress goes with it. Screen time already given for it stays.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Call it off')),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(parentApiProvider).deleteFamilyQuest(quest.id);
      ref.invalidate(familyQuestsProvider);
      messenger.showSnackBar(SnackBar(content: Text('Called off: ${quest.title}.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(familyQuestsProvider);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Family quest', style: text.titleMedium),
        const SizedBox(height: 8),
        AsyncView<List<FamilyQuest>>(
          value: quests,
          onRetry: () => ref.invalidate(familyQuestsProvider),
          builder: (context, all) {
            final quest = currentFamilyQuest(all);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (quest != null) _Quest(quest: quest, onCallOff: () => _callOff(context, ref, quest)),
                if (quest == null || quest.state != FamilyQuestState.running) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _start(context, ref),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
                    icon: const Icon(Icons.groups_rounded),
                    label: Text(quest == null ? 'Start a family quest' : 'Start another one'),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Quest extends StatelessWidget {
  const _Quest({required this.quest, required this.onCallOff});

  final FamilyQuest quest;
  final VoidCallback onCallOff;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = QuestColors.of(context);
    final tint = quest.reached ? colors.approved : colors.xp;

    final (badge, note) = switch (quest.state) {
      FamilyQuestState.done => (
          'Finished!',
          quest.rewardedAt == null
              ? 'Everyone who helped has earned ${formatMinutes(quest.rewardMinutesEach)}.'
              : 'Everyone who helped earned ${formatMinutes(quest.rewardMinutesEach)}.',
        ),
      FamilyQuestState.upcoming => (
          'Starts ${formatDay(context, quest.startsAt)}',
          '${formatMinutes(quest.rewardMinutesEach)} each when the household finishes ${quest.targetCount}.',
        ),
      FamilyQuestState.missed => (
          'Ended',
          'The window closed with ${quest.questsLeft} to go. Screen time was not given.',
        ),
      FamilyQuestState.running => (
          'Ends ${formatDay(context, quest.endsAt)}',
          '${quest.questsLeft} to go, then ${formatMinutes(quest.rewardMinutesEach)} each.',
        ),
    };

    return Card(
      margin: EdgeInsets.zero,
      color: tint.fill,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quest.title,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: tint.ink),
                  ),
                ),
                IconButton(
                  tooltip: 'Call it off',
                  onPressed: onCallOff,
                  icon: Icon(Icons.close_rounded, color: tint.ink),
                ),
              ],
            ),
            Text(
              '${quest.done} of ${quest.targetCount} quests · $badge',
              style: text.bodyMedium?.copyWith(color: tint.ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: quest.fraction,
                  minHeight: 10,
                  color: tint.ink,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(note, style: text.bodyMedium?.copyWith(color: tint.ink)),
            if (quest.helpers.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Helping: ${[for (final helper in quest.helpers) '${helper.name} ${helper.quests}'].join(' · ')}',
                style: text.bodySmall?.copyWith(color: tint.ink),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                'Nobody has finished a quest for it yet.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
