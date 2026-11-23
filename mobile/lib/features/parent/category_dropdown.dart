import 'package:flutter/material.dart';

import '../../core/models/chore.dart';
import 'custom_chore_screen.dart';

/// The chores a list shows for a category: the catalogue's chores in it, or,
/// for Custom chore, the parent's own.
List<ChoreTemplate> inCategory(List<ChoreTemplate> chores, String category) => [
      for (final chore in chores)
        if (category == ChoreCategory.custom ? chore.isCustom : !chore.isCustom && chore.category == category) chore,
    ];

/// The category a list opens on: the first one with something in it, or the
/// first of all.
String firstCategoryWith(List<ChoreCategory> categories, List<ChoreTemplate> chores) {
  for (final category in categories) {
    if (!category.isCustom && inCategory(chores, category.key).isNotEmpty) return category.key;
  }
  return categories.isEmpty ? ChoreCategory.custom : categories.first.key;
}

const customChoreWarning = 'Custom chores cannot be checked by movement. Your child will take a '
    'Before and After photo and you will check them yourself.';

/// The warning a parent must accept before Custom chore opens (PS-2). True
/// only when they accept it; closing it any other way is a no.
Future<bool> acceptCustomChoreWarning(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.visibility_rounded),
      title: const Text('A custom chore is checked by you'),
      content: const Text(customChoreWarning),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Go back')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('I understand')),
      ],
    ),
  );
  return accepted ?? false;
}

/// The category a parent picks first (PS-1): the server's categories in its
/// order, Custom chore last. Custom chore takes effect only once its warning
/// is accepted; otherwise the category stays as it was.
class CategoryDropdown extends StatelessWidget {
  const CategoryDropdown({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  final List<ChoreCategory> categories;
  final String value;
  final ValueChanged<String> onChanged;

  Future<void> _pick(BuildContext context, String? key) async {
    if (key == null || key == value) return;
    if (key == ChoreCategory.custom && !await acceptCustomChoreWarning(context)) return;
    onChanged(key);
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(Icons.category_rounded),
        contentPadding: EdgeInsets.fromLTRB(12, 4, 8, 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: categories.any((c) => c.key == value) ? value : null,
          isExpanded: true,
          items: [
            for (final category in categories)
              DropdownMenuItem(
                value: category.key,
                child: Row(
                  children: [
                    if (category.isCustom) ...[
                      const Icon(Icons.edit_note_rounded, size: 20),
                      const SizedBox(width: 6),
                    ],
                    Expanded(child: Text(category.name, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
          onChanged: (key) => _pick(context, key),
        ),
      ),
    );
  }
}

/// What Custom chore shows once the warning is accepted: the parent's own
/// custom chores, and a button to make a new one. [tile] draws each chore as
/// the list around it draws the catalogue's; [onMade] receives a new one.
class CustomChoresSection extends StatelessWidget {
  const CustomChoresSection({
    super.key,
    required this.chores,
    required this.tile,
    required this.onMade,
  });

  final List<ChoreTemplate> chores;
  final Widget Function(ChoreTemplate chore) tile;
  final ValueChanged<ChoreTemplate> onMade;

  Future<void> _new(BuildContext context) async {
    final made = await Navigator.of(context).push<ChoreTemplate>(
      MaterialPageRoute(builder: (_) => const CustomChoreScreen()),
    );
    if (made != null) onMade(made);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          chores.isEmpty ? "You haven't made a custom chore yet." : 'Your custom chores',
          style: chores.isEmpty ? text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant) : text.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final chore in chores) tile(chore),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _new(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New custom chore'),
        ),
      ],
    );
  }
}
