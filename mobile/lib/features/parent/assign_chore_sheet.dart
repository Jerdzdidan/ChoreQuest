import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/api_dates.dart';
import '../../core/models/child_profile.dart';
import '../../core/models/chore.dart';
import '../../shared/avatars.dart';
import '../../shared/chore_icons.dart';
import '../../shared/format.dart';
import '../../shared/inline_error.dart';
import '../../shared/quest_places.dart';
import 'parent_api.dart';
import 'parent_providers.dart';

/// Assign a chore to one or more children, or change one already assigned.
/// Pops `true` on success.
class AssignChoreSheet extends ConsumerStatefulWidget {
  const AssignChoreSheet({
    super.key,
    required this.template,
    this.child,
    this.existing,
  });

  /// Ticked to start with. The parent can add brothers and sisters, and
  /// each gets an assignment of their own.
  final ChildProfile? child;
  final ChoreTemplate template;

  /// Present when editing. The repeat pattern cannot be changed after the
  /// fact, so editing covers points and the finish-by time.
  final Assignment? existing;

  @override
  ConsumerState<AssignChoreSheet> createState() => _AssignChoreSheetState();
}

class _AssignChoreSheetState extends ConsumerState<AssignChoreSheet> {
  late int _points = widget.existing?.points ?? widget.template.defaultPoints;
  late ClockTime? _due = widget.existing?.dueTime;
  late QuestLocation _location =
      widget.existing?.location ?? widget.template.location;
  Recurrence _recurrence = Recurrence.daily;
  DateTime? _date;
  // Ticked to start with, unless this chore is outside that child's age
  // range: the server would refuse it, and the checkbox shows it unticked.
  late final Set<int> _selected = {
    if (widget.child case final child?
        when child.age >= widget.template.minAge &&
            child.age <= widget.template.maxAge)
      child.id,
  };

  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  Future<void> _pickTime() async {
    final initial = _due ?? const ClockTime(17, 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: 'Finish by',
    );
    if (picked != null) {
      setState(() => _due = ClockTime(picked.hour, picked.minute));
    }
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _run(int childId, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(assignmentsProvider(childId));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() {
    final api = ref.read(parentApiProvider);
    final existing = widget.existing;

    if (existing != null) {
      return _run(
        existing.childId,
        () => api.updateAssignment(
          existing.id,
          points: _points,
          dueTime: _due,
          clearDueTime: _due == null,
          location: _location,
        ),
      );
    }

    if (_selected.isEmpty) {
      setState(() => _error = 'Choose at least one child.');
      return Future.value();
    }

    if (_recurrence == Recurrence.once && _date == null) {
      setState(() => _error = 'Choose the day this chore is for.');
      return Future.value();
    }

    return _assignToSelected(api);
  }

  /// One assignment per ticked child, so each child's progress is their own.
  /// A child the server refuses stays ticked with the reason shown; the
  /// others are assigned and unticked, so trying again never doubles them.
  Future<void> _assignToSelected(ParentApi api) async {
    final children = ref.read(childrenProvider).value ?? const <ChildProfile>[];
    String nameOf(int id) {
      for (final child in children) {
        if (child.id == id) return child.name;
      }
      return widget.child?.id == id ? widget.child!.name : 'A child';
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final failures = <String>[];
    for (final childId in _selected.toList()) {
      try {
        await api.assign(
          childId: childId,
          templateId: widget.template.id,
          points: _points,
          dueTime: _due,
          recurrence: _recurrence,
          scheduledDate: _date,
          location: _location,
        );
        ref.invalidate(assignmentsProvider(childId));
        _selected.remove(childId);
      } on ApiException catch (e) {
        failures.add('${nameOf(childId)}: ${e.message}');
      }
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = failures.join('\n');
    });
  }

  String _assignLabel(List<ChildProfile>? children) {
    if (_selected.length != 1) {
      return _selected.isEmpty ? 'Assign' : 'Assign to ${_selected.length} children';
    }
    final id = _selected.first;
    for (final child in children ?? const <ChildProfile>[]) {
      if (child.id == id) return 'Assign to ${child.name}';
    }
    return widget.child?.id == id ? 'Assign to ${widget.child!.name}' : 'Assign';
  }

  Future<void> _remove() {
    final existing = widget.existing;
    if (existing == null) return Future.value();
    return _run(
      existing.childId,
      () => ref.read(parentApiProvider).removeAssignment(existing.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    // Minutes are shown for a single child; brothers and sisters can each
    // have their own rate.
    final singleChildId = widget.existing?.childId ??
        (_selected.length == 1 ? _selected.first : null);
    final rule =
        singleChildId == null ? null : ref.watch(ruleProvider(singleChildId));
    final minutesPerPoint = rule != null && rule.hasValue
        ? rule.requireValue.minutesPerPoint
        : null;
    final children = _editing ? null : ref.watch(childrenProvider);
    final due = _due;
    final date = _date;
    final error = _error;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ChoreIcon(
                  icon: widget.template.icon,
                  category: widget.template.category,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.template.name, style: text.titleLarge),
                ),
              ],
            ),
            if (widget.template.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.template.description,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (children != null) ...[
              const SizedBox(height: 20),
              Text('For', style: text.titleSmall),
              const SizedBox(height: 4),
              if (children.hasValue)
                for (final child in children.requireValue)
                  _ChildCheckbox(
                    child: child,
                    template: widget.template,
                    selected: _selected.contains(child.id),
                    onChanged: _busy
                        ? null
                        : (on) => setState(
                              () => on
                                  ? _selected.add(child.id)
                                  : _selected.remove(child.id),
                            ),
                  )
              else if (children.hasError)
                Text(
                  "Couldn't load your children. Close this and try again.",
                  style: text.bodySmall?.copyWith(color: scheme.error),
                )
              else
                const LinearProgressIndicator(),
            ],
            const SizedBox(height: 20),
            Text('Points', style: text.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Fewer points',
                  onPressed: _busy || _points <= 1
                      ? null
                      : () => setState(() => _points--),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('$_points', style: text.headlineMedium),
                      if (minutesPerPoint != null)
                        Text(
                          'earns ${formatMinutes(_points * minutesPerPoint)}',
                          style: text.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'More points',
                  onPressed: _busy || _points >= 100
                      ? null
                      : () => setState(() => _points++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Finish by'),
              subtitle: Text(
                due == null
                    ? 'Any time that day'
                    : localizations.formatTimeOfDay(
                        TimeOfDay(hour: due.hour, minute: due.minute),
                      ),
              ),
              trailing: due == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove the time',
                      icon: const Icon(Icons.clear),
                      onPressed: _busy ? null : () => setState(() => _due = null),
                    ),
              onTap: _busy ? null : _pickTime,
            ),
            const SizedBox(height: 8),
            Text('Where', style: text.titleSmall),
            const SizedBox(height: 2),
            Text(
              "Groups the quest on your child's quest map.",
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
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
                    selected: _location == place,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _location = place),
                  ),
              ],
            ),
            if (!_editing) ...[
              const SizedBox(height: 8),
              SegmentedButton<Recurrence>(
                segments: const [
                  ButtonSegment(
                    value: Recurrence.daily,
                    label: Text('Every day'),
                    icon: Icon(Icons.repeat),
                  ),
                  ButtonSegment(
                    value: Recurrence.once,
                    label: Text('One day'),
                    icon: Icon(Icons.event),
                  ),
                ],
                selected: {_recurrence},
                onSelectionChanged: _busy
                    ? null
                    : (selection) =>
                        setState(() => _recurrence = selection.first),
              ),
              if (_recurrence == Recurrence.once)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Day'),
                  subtitle: Text(
                    date == null
                        ? 'Choose a day'
                        : localizations.formatMediumDate(date),
                  ),
                  onTap: _busy ? null : _pickDate,
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              InlineError(error),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_editing ? 'Save' : _assignLabel(children?.value)),
            ),
            if (_editing)
              TextButton(
                onPressed: _busy ? null : _remove,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('Remove this chore'),
              ),
          ],
        ),
      ),
    );
  }
}

/// One child the chore can go to. A chore outside the child's age range is
/// shown but cannot be ticked: the server would refuse it, and saying why
/// here is kinder than an error after pressing Assign.
class _ChildCheckbox extends StatelessWidget {
  const _ChildCheckbox({
    required this.child,
    required this.template,
    required this.selected,
    required this.onChanged,
  });

  final ChildProfile child;
  final ChoreTemplate template;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final suits = child.age >= template.minAge && child.age <= template.maxAge;
    final change = onChanged;

    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: Opacity(
        opacity: suits ? 1 : 0.4,
        child: AvatarBadge(child.avatar, size: 40),
      ),
      title: Text(child.name),
      subtitle: suits
          ? null
          : Text('This chore is for ages ${template.minAge} to ${template.maxAge}'),
      value: suits && selected,
      onChanged: !suits || change == null ? null : (on) => change(on ?? false),
    );
  }
}
