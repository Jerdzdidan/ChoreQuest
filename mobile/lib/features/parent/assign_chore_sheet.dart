import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/api_dates.dart';
import '../../core/models/child_profile.dart';
import '../../core/models/chore.dart';
import '../../shared/chore_icons.dart';
import '../../shared/format.dart';
import '../../shared/inline_error.dart';
import 'parent_providers.dart';

/// Assign a chore, or change one already assigned. Pops `true` on success.
class AssignChoreSheet extends ConsumerStatefulWidget {
  const AssignChoreSheet({
    super.key,
    required this.child,
    required this.template,
    this.existing,
  });

  final ChildProfile child;
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
  Recurrence _recurrence = Recurrence.daily;
  DateTime? _date;

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

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(assignmentsProvider(widget.child.id));
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
        () => api.updateAssignment(
          existing.id,
          points: _points,
          dueTime: _due,
          clearDueTime: _due == null,
        ),
      );
    }

    if (_recurrence == Recurrence.once && _date == null) {
      setState(() => _error = 'Choose the day this chore is for.');
      return Future.value();
    }

    return _run(
      () => api.assign(
        childId: widget.child.id,
        templateId: widget.template.id,
        points: _points,
        dueTime: _due,
        recurrence: _recurrence,
        scheduledDate: _date,
      ),
    );
  }

  Future<void> _remove() {
    final existing = widget.existing;
    if (existing == null) return Future.value();
    return _run(() => ref.read(parentApiProvider).removeAssignment(existing.id));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final rule = ref.watch(ruleProvider(widget.child.id));
    final minutesPerPoint =
        rule.hasValue ? rule.requireValue.minutesPerPoint : null;
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
                  : Text(_editing ? 'Save' : 'Assign to ${widget.child.name}'),
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
