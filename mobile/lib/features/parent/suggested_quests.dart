import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chore.dart';
import '../../shared/async_view.dart';
import '../../shared/chore_icons.dart';
import '../../shared/difficulty_xp.dart';
import '../../shared/format.dart';
import 'assign_chore_sheet.dart';
import 'parent_providers.dart';
import 'quest_catalogue_screen.dart';

/// How many suggestions the Board shows before sending the parent to the
/// whole catalogue.
const suggestedQuestCount = 5;

/// Chores in the catalogue that nobody in the household has (BD2), in the
/// catalogue's own order.
///
/// Read from what the Board already loads: the catalogue, the children, and
/// each child's chores. A chore given to any child, to any of them, drops
/// out; a chore paused for everyone comes back.
final suggestedQuestsProvider = FutureProvider.autoDispose<List<ChoreTemplate>>((ref) async {
  final catalogue = (await ref.watch(fullCatalogueProvider.future)).chores;
  final children = await ref.watch(childrenProvider.future);

  final given = <int>{};
  for (final child in children) {
    for (final assignment in await ref.watch(assignmentsProvider(child.id).future)) {
      if (assignment.isActive) given.add(assignment.chore.id);
    }
  }

  return [
    for (final template in catalogue)
      if (!given.contains(template.id)) template,
  ];
});

/// A short list of chores nobody has yet, each one tap from being given to
/// one child or several (BD3). The whole catalogue is a tap away (PQ1).
class SuggestedQuests extends ConsumerWidget {
  const SuggestedQuests({super.key});

  Future<void> _give(BuildContext context, WidgetRef ref, ChoreTemplate template) async {
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AssignChoreSheet(template: template),
    );
    if (assigned != true || !context.mounted) return;
    ref.invalidate(assignmentsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Assigned: ${template.name}.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(suggestedQuestsProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Quests to give out', style: text.titleMedium)),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QuestCatalogueScreen()),
              ),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AsyncView<List<ChoreTemplate>>(
          value: suggestions,
          onRetry: () => ref.invalidate(suggestedQuestsProvider),
          builder: (context, all) {
            if (all.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Every chore in the catalogue is already given out.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final template in all.take(suggestedQuestCount))
                  _SuggestionTile(template: template, onGive: () => _give(context, ref, template)),
                if (all.length > suggestedQuestCount)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${all.length - suggestedQuestCount} more in the catalogue.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.template, required this.onGive});

  final ChoreTemplate template;
  final VoidCallback onGive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tier = difficultyStyleFor(template.difficulty);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            ChoreIcon(icon: template.icon, category: template.category, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${template.difficulty.label} · ${pointsLabel(template.defaultPoints)} · ages ${template.minAge}–${template.maxAge}',
                    style: text.bodySmall?.copyWith(color: tier.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onGive,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: scheme.onSecondaryContainer),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Give'),
            ),
          ],
        ),
      ),
    );
  }
}
