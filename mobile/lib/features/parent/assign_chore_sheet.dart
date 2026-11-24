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
import '../../shared/ringtones.dart';
import '../../shared/schedule_text.dart';
import '../../shared/strap.dart';
import '../../shared/verification_tag.dart';
import 'parent_api.dart';
import 'parent_providers.dart';
import 'ringtone_field.dart';

/// Assign a chore to one or more children, or change one already assigned.
/// Pops `true` on success.
///
/// One-time or daily comes first (PS-3), and decides what is asked below
/// it: a one-time quest has a day, an alarm and a ringtone (PS-4); a daily
/// quest has the weekdays it repeats on, an alarm and a ringtone (PS-5).
/// Everything, the repeat included, can be changed later. Every quest is
/// watched through the child's phone on a strap, and a quest the model
/// checks says so (CAM-3).
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

  /// Present when editing.
  final Assignment? existing;

  @override
  ConsumerState<AssignChoreSheet> createState() => _AssignChoreSheetState();
}

class _AssignChoreSheetState extends ConsumerState<AssignChoreSheet> {
  late int _points = widget.existing?.points ?? widget.template.defaultPoints;
  late QuestLocation _location = widget.existing?.location ?? widget.template.location;
  late Recurrence _recurrence = widget.existing?.recurrence ?? Recurrence.daily;
  late DateTime? _date = widget.existing?.scheduledDate;
  late final Set<int> _days = {...widget.existing?.daysOfWeek ?? everyDay};
  late ClockTime? _alarm = widget.existing?.dueTime;
  late String _ringtone = widget.existing?.ringtoneKey ?? defaultRingtone;

  // Ticked to start with, unless this chore is outside that child's age
  // range: the server would refuse it, and the checkbox shows it unticked.
  late final Set<int> _selected = {
    if (widget.child case final child?
        when child.age >= widget.template.minAge && child.age <= widget.template.maxAge)
      child.id,
  };

  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  String _nameOf(int id) {
    for (final child in ref.read(childrenProvider).value ?? const <ChildProfile>[]) {
      if (child.id == id) return child.name;
    }
    return widget.child?.id == id ? widget.child!.name : 'Your child';
  }

  Future<void> _pickTime() async {
    final initial = _alarm ?? const ClockTime(17, 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: 'Alarm',
    );
    if (picked != null) {
      setState(() => _alarm = ClockTime(picked.hour, picked.minute));
    }
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: today.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _setChild(int id, bool on) {
    setState(() => on ? _selected.add(id) : _selected.remove(id));
  }

  /// The schedule as it stands, or what is missing from it.
  (QuestSchedule?, String?) _schedule() {
    final daily = _recurrence == Recurrence.daily;
    if (!daily && _date == null) return (null, 'Choose the day this quest is for.');
    if (daily && _days.isEmpty) return (null, 'Choose at least one day of the week.');

    final days = [..._days]..sort();
    return (
      QuestSchedule(
        recurrence: _recurrence,
        scheduledDate: daily ? null : _date,
        // All seven is "every day", which the server keeps as no list at all.
        daysOfWeek: daily && _days.length < 7 ? days : null,
        alarmTime: _alarm,
        ringtoneKey: _ringtone,
        alarmEnabled: widget.existing?.alarmEnabled ?? true,
      ),
      null,
    );
  }

  Future<void> _save() async {
    final api = ref.read(parentApiProvider);
    final existing = widget.existing;

    if (existing == null && _selected.isEmpty) {
      setState(() => _error = 'Choose at least one child.');
      return;
    }
    final (schedule, problem) = _schedule();
    if (schedule == null) {
      setState(() => _error = problem);
      return;
    }

    if (existing != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        await api.updateAssignment(existing.id, points: _points, location: _location, schedule: schedule);
        ref.invalidate(assignmentsProvider(existing.childId));
        if (mounted) Navigator.of(context).pop(true);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    await _assignToSelected(api, schedule);
  }

  /// One assignment per ticked child, so each child's progress is their own.
  /// A child the server refuses stays ticked with the reason shown; the
  /// others are assigned and unticked, so trying again never doubles them.
  Future<void> _assignToSelected(ParentApi api, QuestSchedule schedule) async {
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
          schedule: schedule,
          location: _location,
        );
        ref.invalidate(assignmentsProvider(childId));
        _selected.remove(childId);
      } on ApiException catch (e) {
        failures.add('${_nameOf(childId)}: ${e.message}');
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

  Future<void> _remove() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(parentApiProvider).removeAssignment(existing.id);
      ref.invalidate(assignmentsProvider(existing.childId));
      if (mounted) Navigator.of(context).pop(true);
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
    final localizations = MaterialLocalizations.of(context);
    // Minutes are shown for a single child; brothers and sisters can each
    // have their own rate.
    final singleChildId = widget.existing?.childId ?? (_selected.length == 1 ? _selected.first : null);
    final rule = singleChildId == null ? null : ref.watch(ruleProvider(singleChildId));
    final minutesPerPoint = rule != null && rule.hasValue ? rule.requireValue.minutesPerPoint : null;
    final children = _editing ? null : ref.watch(childrenProvider);
    final daily = _recurrence == Recurrence.daily;
    final alarm = _alarm;
    final date = _date;
    final error = _error;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ChoreIcon(icon: widget.template.icon, category: widget.template.category, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.template.name, style: text.titleLarge),
                      const SizedBox(height: 4),
                      VerificationTag(widget.template.verificationMode),
                    ],
                  ),
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
            // Decision 1: the model sees the chore only from a phone on a strap.
            if (widget.template.verificationMode == VerificationMode.motion) ...[
              const SizedBox(height: 12),
              const StrapNotice(text: strapAssignWarning),
            ],
            const SizedBox(height: 16),
            // PS-3: asked first, and it decides the fields below.
            SegmentedButton<Recurrence>(
              segments: const [
                ButtonSegment(value: Recurrence.once, label: Text('One-time task'), icon: Icon(Icons.event)),
                ButtonSegment(value: Recurrence.daily, label: Text('Daily task'), icon: Icon(Icons.repeat)),
              ],
              selected: {_recurrence},
              onSelectionChanged: _busy ? null : (selection) => setState(() => _recurrence = selection.first),
            ),
            if (children != null) ...[
              const SizedBox(height: 16),
              Text('For', style: text.titleSmall),
              const SizedBox(height: 4),
              if (children.hasValue)
                for (final child in children.requireValue)
                  _ChildCheckbox(
                    child: child,
                    template: widget.template,
                    selected: _selected.contains(child.id),
                    onChanged: _busy ? null : (on) => _setChild(child.id, on),
                  )
              else if (children.hasError)
                Text(
                  "Couldn't load your children. Close this and try again.",
                  style: text.bodySmall?.copyWith(color: scheme.error),
                )
              else
                const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            if (daily)
              _Weekdays(
                days: _days,
                enabled: !_busy,
                onChanged: (days) => setState(() => _days
                  ..clear()
                  ..addAll(days)),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Day'),
                subtitle: Text(date == null ? 'Choose a day' : localizations.formatMediumDate(date)),
                onTap: _busy ? null : _pickDate,
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm_rounded),
              title: const Text('Alarm'),
              subtitle: Text(alarm == null ? 'No alarm' : alarmText(alarm, localizations)),
              trailing: alarm == null
                  ? null
                  : IconButton(
                      tooltip: 'Remove the alarm',
                      icon: const Icon(Icons.clear),
                      onPressed: _busy ? null : () => setState(() => _alarm = null),
                    ),
              onTap: _busy ? null : _pickTime,
            ),
            RingtoneField(
              value: _ringtone,
              enabled: !_busy,
              onChanged: (key) => setState(() => _ringtone = key),
            ),
            const SizedBox(height: 16),
            Text('Points', style: text.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Fewer points',
                  onPressed: _busy || _points <= 1 ? null : () => setState(() => _points--),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('$_points', style: text.headlineMedium),
                      if (minutesPerPoint != null)
                        Text('earns ${formatMinutes(_points * minutesPerPoint)}', style: text.bodySmall),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'More points',
                  onPressed: _busy || _points >= 100 ? null : () => setState(() => _points++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                    onSelected: _busy ? null : (_) => setState(() => _location = place),
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

/// The weekdays a daily quest repeats on (PS-5): one chip a day, Monday
/// first, and quick picks for every day, weekdays and the weekend.
class _Weekdays extends StatelessWidget {
  const _Weekdays({required this.days, required this.enabled, required this.onChanged});

  final Set<int> days;
  final bool enabled;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Repeats on', style: text.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final MapEntry(key: day, value: name) in weekdayShort.entries)
              FilterChip(
                showCheckmark: false,
                label: Text(name),
                selected: days.contains(day),
                onSelected: enabled ? (on) => onChanged(on ? {...days, day} : ({...days}..remove(day))) : null,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            for (final (label, pick) in const [('Every day', everyDay), ('Weekdays', weekdays), ('Weekend', weekend)])
              TextButton(onPressed: enabled ? () => onChanged({...pick}) : null, child: Text(label)),
          ],
        ),
      ],
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
      subtitle: suits ? null : Text('This chore is for ages ${template.minAge} to ${template.maxAge}'),
      value: suits && selected,
      onChanged: !suits || change == null ? null : (on) => change(on ?? false),
    );
  }
}
