import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_profile.dart';
import '../../core/models/chore.dart';
import '../../shared/async_view.dart';
import '../../shared/chore_icons.dart';
import '../../shared/format.dart';
import 'assign_chore_sheet.dart';
import 'parent_providers.dart';

/// The catalogue, already filtered by the server to this child's age.
class CataloguePickerScreen extends ConsumerWidget {
  const CataloguePickerScreen({super.key, required this.child});

  final ChildProfile child;

  Future<void> _assign(BuildContext context, ChoreTemplate template) async {
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AssignChoreSheet(child: child, template: template),
    );
    if (assigned == true && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider(child.id));
    final assignments = ref.watch(assignmentsProvider(child.id));
    final assignedLocations = assignments.hasValue
        ? {for (final a in assignments.requireValue) a.chore.id: a.location}
        : <int, QuestLocation>{};
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Chores for ${child.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Only chores suited to age ${child.age} are shown.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          AsyncView<List<ChoreTemplate>>(
            value: catalogue,
            onRetry: () => ref.invalidate(catalogueProvider(child.id)),
            builder: (context, list) => list.isEmpty
                ? Text(
                    'No chores in the catalogue suit age ${child.age}. '
                    'ChoreQuest covers ages 4 to 10.',
                  )
                : Column(
                    children: [
                      for (final template in list)
                        _TemplateTile(
                          template: template,
                          assignedAt: assignedLocations[template.id],
                          onTap: () => _assign(context, template),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.assignedAt,
    required this.onTap,
  });

  final ChoreTemplate template;

  /// Where this chore is already assigned, or null when it is not.
  final QuestLocation? assignedAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final place = assignedAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChoreIcon(icon: template.icon, category: template.category, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.name, style: text.titleMedium),
                    if (template.description.isNotEmpty)
                      Text(
                        template.description,
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Tag(label: pointsLabel(template.defaultPoints)),
                        if (template.modelVerifiable)
                          _Tag(
                            label: 'Checked automatically',
                            colour: scheme.primaryContainer,
                          ),
                        if (place != null)
                          _Tag(
                            label: place == QuestLocation.other
                                ? 'Already assigned'
                                : 'Already assigned · ${place.label}',
                            colour: scheme.tertiaryContainer,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.colour});

  final String label;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colour ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
