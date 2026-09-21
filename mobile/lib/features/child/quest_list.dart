import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chore.dart';
import '../../core/models/submission.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../core/uploads/pending_upload.dart';
import '../../shared/async_view.dart';
import 'child_api.dart';
import 'child_providers.dart';
import 'chore_camera_screen.dart';
import 'chore_card.dart';

/// The photos that decide where each of today's quests stands: those sent,
/// and those still saved on the phone.
///
/// Either list counts as empty until it loads, so a slow connection shows a
/// quest as still to do rather than hiding it.
class QuestStates {
  const QuestStates({required this.sent, required this.saved});

  /// Reads both lists for [childId], so the caller rebuilds when either
  /// changes. Call it from a build method.
  factory QuestStates.watch(WidgetRef ref, int childId) {
    final sent = ref.watch(mySubmissionsProvider);
    final saved = ref.watch(pendingUploadsProvider(childId));
    return QuestStates(
      sent: sent.hasValue ? sent.requireValue : const <Submission>[],
      saved: saved.hasValue ? saved.requireValue : const <PendingUpload>[],
    );
  }

  final List<Submission> sent;
  final List<PendingUpload> saved;

  ChoreState of(Assignment assignment, DateTime today) =>
      choreStateFor(assignment, sent, today, saved: saved);
}

/// Opens the camera for [assignment], and refreshes everything on the way
/// back so the quest shows where it now stands.
Future<void> openQuestCamera(BuildContext context, WidgetRef ref, Assignment assignment) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ChoreCameraScreen(assignment: assignment)),
  );
  if (context.mounted) refreshChildData(ref);
}

/// Today's quests as mission cards: every quest, or only those at [place].
///
/// This is the list the home screen showed before the quest map (U10). A
/// place on the map opens it for that place.
class QuestList extends ConsumerWidget {
  const QuestList({super.key, this.place});

  /// Only the quests here, or every quest when null.
  final QuestLocation? place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ChildSession s) => s,
      _ => null,
    };
    if (me == null) return const SizedBox.shrink();

    final chores = ref.watch(todayChoresProvider);
    final states = QuestStates.watch(ref, me.id);
    final balance = ref.watch(balanceProvider);
    final perPoint = balance.hasValue ? balance.requireValue.minutesPerPoint : null;
    final place = this.place;

    return AsyncView<TodayChores>(
      value: chores,
      onRetry: () => refreshChildData(ref),
      builder: (context, today) {
        final quests = [
          for (final assignment in today.chores)
            if (place == null || assignment.location == place) assignment,
        ];
        if (quests.isEmpty) {
          return NothingToday(place == null ? 'No quests today!' : 'No quests here today!');
        }

        return Column(
          children: [
            for (final assignment in quests)
              ChoreCard(
                assignment: assignment,
                state: states.of(assignment, today.date),
                minutesPerPoint: perPoint,
                onTap: () => openQuestCamera(context, ref, assignment),
              ),
          ],
        );
      },
    );
  }
}

/// A sunny picture and a line, for when there is nothing to do.
class NothingToday extends StatelessWidget {
  const NothingToday(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.wb_sunny_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
