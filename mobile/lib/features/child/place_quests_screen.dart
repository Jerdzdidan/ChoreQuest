import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chore.dart';
import '../../shared/quest_places.dart';
import '../../shared/theme.dart';
import 'child_providers.dart';
import 'quest_list.dart';

/// One place on the quest map, and today's quests there.
///
/// The same mission cards as everywhere else, just those at this place. The
/// home screen keeps checking for a grown-up's decisions underneath, so a
/// quest approved while this is open turns to done here too.
class PlaceQuestsScreen extends ConsumerWidget {
  const PlaceQuestsScreen({super.key, required this.place});

  final QuestLocation place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = QuestColors.of(context).place(place);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: tint.fill,
              child: Icon(iconForLocation(place), size: 22, color: tint.ink),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(place.label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshChildData(ref);
          await ref.read(todayChoresProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [QuestList(place: place)],
        ),
      ),
    );
  }
}
