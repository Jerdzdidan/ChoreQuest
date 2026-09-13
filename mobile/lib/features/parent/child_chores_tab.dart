import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/child_profile.dart';
import '../../core/models/chore.dart';
import '../../shared/async_view.dart';
import '../../shared/chore_icons.dart';
import '../../shared/format.dart';
import 'assign_chore_sheet.dart';
import 'catalogue_picker_screen.dart';
import 'parent_providers.dart';

/// The chores a child has been given, each switchable on and off.
class ChildChoresTab extends ConsumerWidget {
  const ChildChoresTab({super.key, required this.child});

  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(assignmentsProvider(child.id));
    final rule = ref.watch(ruleProvider(child.id));
    final minutesPerPoint =
        rule.hasValue ? rule.requireValue.minutesPerPoint : null;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'assign-chore-${child.id}',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CataloguePickerScreen(child: child),
          ),
        ),
        icon: const Icon(Icons.add_task),
        label: const Text('Assign chore'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(assignmentsProvider(child.id).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            AsyncView<List<Assignment>>(
              value: assignments,
              onRetry: () => ref.invalidate(assignmentsProvider(child.id)),
              builder: (context, list) => list.isEmpty
                  ? _NoChoresYet(name: child.name)
                  : Column(
                      children: [
                        for (final assignment in list)
                          _AssignmentTile(
                            child: child,
                            assignment: assignment,
                            minutesPerPoint: minutesPerPoint,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoChoresYet extends StatelessWidget {
  const _NoChoresYet({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        '$name has no chores yet. Tap "Assign chore" to choose some.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _AssignmentTile extends ConsumerWidget {
  const _AssignmentTile({
    required this.child,
    required this.assignment,
    required this.minutesPerPoint,
  });

  final ChildProfile child;
  final Assignment assignment;
  final int? minutesPerPoint;

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    bool active,
  ) async {
    try {
      await ref
          .read(parentApiProvider)
          .updateAssignment(assignment.id, isActive: active);
      ref.invalidate(assignmentsProvider(child.id));
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chore = assignment.chore;
    final localizations = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final perPoint = minutesPerPoint;
    final due = assignment.dueTime;
    final scheduled = assignment.scheduledDate;

    final details = [
      perPoint == null
          ? pointsLabel(assignment.points)
          : '${pointsLabel(assignment.points)} '
              '(${formatMinutes(assignment.points * perPoint)})',
      if (assignment.recurrence == Recurrence.daily)
        'Every day'
      else if (scheduled != null)
        'On ${localizations.formatMediumDate(scheduled)}'
      else
        'One day',
      if (due != null)
        'by ${localizations.formatTimeOfDay(TimeOfDay(hour: due.hour, minute: due.minute))}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        leading: Opacity(
          opacity: assignment.isActive ? 1 : 0.4,
          child: ChoreIcon(icon: chore.icon, category: chore.category, size: 44),
        ),
        title: Text(chore.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(details),
            if (chore.modelVerifiable)
              Text(
                'Photo checked automatically',
                style: TextStyle(color: scheme.primary),
              ),
            if (!assignment.isActive)
              Text('Paused', style: TextStyle(color: scheme.tertiary)),
          ],
        ),
        trailing: Switch(
          value: assignment.isActive,
          onChanged: (active) => _setActive(context, ref, active),
        ),
        onTap: () => showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => AssignChoreSheet(
            child: child,
            template: chore,
            existing: assignment,
          ),
        ),
      ),
    );
  }
}
