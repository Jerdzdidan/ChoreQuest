import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/chore.dart';
import '../../shared/chore_icons.dart';
import '../../shared/difficulty_xp.dart';
import '../../shared/inline_error.dart';
import '../../shared/quest_places.dart';
import 'parent_providers.dart';

/// A chore the parent makes up (PS-2), reached only after accepting the
/// custom chore warning. Pops the new chore, which then goes through the
/// same one-time or daily choice as any other.
///
/// A scrolling column, not a lazy list: a form inside a lazy list loses its
/// fields, and their validators, once they scroll out of range.
class CustomChoreScreen extends ConsumerStatefulWidget {
  const CustomChoreScreen({super.key});

  @override
  ConsumerState<CustomChoreScreen> createState() => _CustomChoreScreenState();
}

class _CustomChoreScreenState extends ConsumerState<CustomChoreScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _note = TextEditingController();
  var _icon = choreIconKeys.first;
  var _place = QuestLocation.other;
  var _difficulty = QuestDifficulty.easy;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final made = await ref.read(parentApiProvider).createCustomChore(
            name: _name.text.trim(),
            description: _note.text.trim().isEmpty ? null : _note.text.trim(),
            icon: _icon,
            location: _place,
            difficulty: _difficulty,
          );
      // Every list of chores now has one more.
      ref.invalidate(fullCatalogueProvider);
      ref.invalidate(catalogueProvider);
      if (mounted) Navigator.of(context).pop(made);
    } on ApiRejected catch (e) {
      if (mounted) setState(() => _error = e.errorFor('name') ?? e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('New custom chore')),
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.visibility_rounded, color: scheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Manual check: you will check the Before and After photos yourself.',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !_busy,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'Feed the cat'),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Give the chore a name.' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                enabled: !_busy,
                maxLength: 200,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'One scoop, and fresh water'),
              ),
              const SizedBox(height: 12),
              Text('Picture', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in choreIconKeys)
                    Semantics(
                      button: true,
                      selected: key == _icon,
                      label: 'Picture $key',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _busy ? null : () => setState(() => _icon = key),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: key == _icon ? scheme.primary : Colors.transparent, width: 3),
                          ),
                          child: ChoreIcon(icon: key, category: ChoreCategory.custom, size: 40),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Where on the quest map', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final place in QuestLocation.values)
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(iconForLocation(place), size: 18),
                      label: Text(place.label),
                      selected: _place == place,
                      onSelected: _busy ? null : (_) => setState(() => _place = place),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('How hard is it?', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tier in QuestDifficulty.values)
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(difficultyStyleFor(tier).icon, size: 18),
                      label: Text('${tier.label} · ${xpFor(tier)} XP'),
                      selected: _difficulty == tier,
                      onSelected: _busy ? null : (_) => setState(() => _difficulty = tier),
                    ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                InlineError(error),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save chore'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
