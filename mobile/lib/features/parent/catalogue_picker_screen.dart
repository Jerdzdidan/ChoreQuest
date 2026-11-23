import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_profile.dart';
import '../../core/models/chore.dart';
import '../../shared/async_view.dart';
import '../../shared/chore_icons.dart';
import '../../shared/format.dart';
import '../../shared/verification_tag.dart';
import 'assign_chore_sheet.dart';
import 'category_dropdown.dart';
import 'parent_providers.dart';

/// The catalogue, already filtered by the server to this child's age: a
/// category first (PS-1), then that category's chores, or the parent's own
/// custom chores behind their warning (PS-2).
class CataloguePickerScreen extends ConsumerStatefulWidget {
  const CataloguePickerScreen({super.key, required this.child});

  final ChildProfile child;

  @override
  ConsumerState<CataloguePickerScreen> createState() => _CataloguePickerScreenState();
}

class _CataloguePickerScreenState extends ConsumerState<CataloguePickerScreen> {
  String? _category;

  ChildProfile get child => widget.child;

  Future<void> _assign(ChoreTemplate template) async {
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AssignChoreSheet(child: child, template: template),
    );
    if (assigned == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueProvider(child.id));
    final assignments = ref.watch(assignmentsProvider(child.id));
    final assignedLocations = assignments.hasValue
        ? {for (final a in assignments.requireValue) a.chore.id: a.location}
        : <int, QuestLocation>{};
    final scheme = Theme.of(context).colorScheme;

    Widget tile(ChoreTemplate template) => _TemplateTile(
          template: template,
          assignedAt: assignedLocations[template.id],
          onTap: () => _assign(template),
        );

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
          AsyncView<ChoreCatalogue>(
            value: catalogue,
            onRetry: () => ref.invalidate(catalogueProvider(child.id)),
            builder: (context, catalogue) {
              final category = _category ?? firstCategoryWith(catalogue.categories, catalogue.chores);
              final shown = inCategory(catalogue.chores, category);
              final name = catalogue.categories.where((c) => c.key == category).firstOrNull?.name ?? 'this category';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CategoryDropdown(
                    categories: catalogue.categories,
                    value: category,
                    onChanged: (key) => setState(() => _category = key),
                  ),
                  const SizedBox(height: 12),
                  if (category == ChoreCategory.custom)
                    CustomChoresSection(chores: shown, tile: tile, onMade: _assign)
                  else if (shown.isEmpty)
                    Text(
                      'Nothing in $name suits age ${child.age}. Try another category.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    )
                  else
                    for (final template in shown) tile(template),
                ],
              );
            },
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
                        VerificationTag(template.verificationMode),
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
