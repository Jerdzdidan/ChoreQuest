import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chore.dart';
import '../../shared/async_view.dart';
import '../../shared/chore_icons.dart';
import '../../shared/difficulty_xp.dart';
import '../../shared/format.dart';
import '../../shared/quest_places.dart';
import '../../shared/theme.dart';
import '../../shared/verification_tag.dart';
import 'assign_chore_sheet.dart';
import 'category_dropdown.dart';
import 'parent_providers.dart';

/// The catalogue grouped by the place each chore usually happens, in map
/// order, keeping only chores whose name or description contains [query]
/// (any case). A place with nothing left is dropped. Pure, so the same
/// catalogue and query always give the same groups.
List<(QuestLocation, List<ChoreTemplate>)> catalogueByPlace(List<ChoreTemplate> catalogue, String query) {
  final wanted = query.trim().toLowerCase();
  bool matches(ChoreTemplate t) =>
      wanted.isEmpty || t.name.toLowerCase().contains(wanted) || t.description.toLowerCase().contains(wanted);

  return [
    for (final place in QuestLocation.values)
      (place, [for (final t in catalogue) if (t.location == place && matches(t)) t]),
  ].where((group) => group.$2.isNotEmpty).toList();
}

/// Every chore in the catalogue, for a parent who wants to see them all
/// (PQ1): a category first (PS-1), its chores grouped by place, and each one
/// tap away from being given to one child or several (BD3). A search looks
/// through every category at once, whichever is chosen.
///
/// The Board's short list of suggestions (BD2) is separate; this is the whole
/// catalogue, every age.
class QuestCatalogueScreen extends ConsumerStatefulWidget {
  const QuestCatalogueScreen({super.key, this.showAppBar = true});

  /// False when the screen is the Quests tab, under the shell's own bar.
  final bool showAppBar;

  @override
  ConsumerState<QuestCatalogueScreen> createState() => _QuestCatalogueScreenState();
}

class _QuestCatalogueScreenState extends ConsumerState<QuestCatalogueScreen> {
  final _search = TextEditingController();
  var _query = '';
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _assign(ChoreTemplate template) async {
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AssignChoreSheet(template: template),
    );
    if (assigned != true || !mounted) return;
    // Any child's list of chores may have changed.
    ref.invalidate(assignmentsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Assigned: ${template.name}.')),
    );
  }

  void _clear() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(fullCatalogueProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final body = RefreshIndicator(
      onRefresh: () => ref.refresh(fullCatalogueProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search quests',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(tooltip: 'Clear the search', onPressed: _clear, icon: const Icon(Icons.close_rounded)),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          AsyncView<ChoreCatalogue>(
            value: catalogue,
            onRetry: () => ref.invalidate(fullCatalogueProvider),
            builder: (context, catalogue) {
              final all = catalogue.chores;
              final category = _category ?? firstCategoryWith(catalogue.categories, all);
              final searching = _query.trim().isNotEmpty;
              final dropdown = CategoryDropdown(
                categories: catalogue.categories,
                value: category,
                onChanged: (key) => setState(() => _category = key),
              );

              if (!searching && category == ChoreCategory.custom) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dropdown,
                    const SizedBox(height: 12),
                    CustomChoresSection(
                      chores: inCategory(all, category),
                      tile: (template) => _CatalogueTile(template: template, onTap: () => _assign(template)),
                      onMade: _assign,
                    ),
                  ],
                );
              }

              final groups = searching ? catalogueByPlace(all, _query) : catalogueByPlace(inCategory(all, category), '');
              final shown = groups.fold<int>(0, (sum, group) => sum + group.$2.length);
              if (groups.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dropdown,
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        all.isEmpty
                            ? 'The catalogue is empty.'
                            : searching
                                ? 'No quests match "${_query.trim()}".'
                                : 'Nothing in this category yet.',
                        textAlign: TextAlign.center,
                        style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dropdown,
                  const SizedBox(height: 8),
                  Text(
                    searching
                        ? '$shown of ${all.length} quests, from every category'
                        : '$shown quests. Tap one to assign it.',
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  for (final (place, templates) in groups) ...[
                    const SizedBox(height: 16),
                    _PlaceHeader(place: place, count: templates.length),
                    const SizedBox(height: 8),
                    for (final template in templates)
                      _CatalogueTile(template: template, onTap: () => _assign(template)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );

    if (!widget.showAppBar) return body;
    return Scaffold(appBar: AppBar(title: const Text('Quests')), body: body);
  }
}

class _PlaceHeader extends StatelessWidget {
  const _PlaceHeader({required this.place, required this.count});

  final QuestLocation place;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tint = QuestColors.of(context).place(place);
    final text = Theme.of(context).textTheme;

    return Semantics(
      header: true,
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: tint.fill,
            child: Icon(iconForLocation(place), size: 18, color: tint.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(place.label, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Text('$count', style: text.labelLarge?.copyWith(color: tint.ink, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CatalogueTile extends StatelessWidget {
  const _CatalogueTile({required this.template, required this.onTap});

  final ChoreTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tier = difficultyStyleFor(template.difficulty);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                    Text(template.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (template.description.isNotEmpty)
                      Text(
                        template.description,
                        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Tag(label: template.difficulty.label, icon: tier.icon, fill: tier.background, ink: tier.ink),
                        _Tag(label: pointsLabel(template.defaultPoints)),
                        _Tag(label: 'Ages ${template.minAge}–${template.maxAge}'),
                        VerificationTag(template.verificationMode),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.add_circle_outline_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.icon, this.fill, this.ink});

  final String label;
  final IconData? icon;
  final Color? fill;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = ink ?? scheme.onSurfaceVariant;
    final icon = this.icon;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fill ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colour),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colour, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
