import 'package:flutter/material.dart';

import '../core/models/chore.dart';

/// The picture for each place a quest can happen. Material icons rather than
/// emoji, like the chore icons, so they draw the same on every phone.
IconData iconForLocation(QuestLocation location) => switch (location) {
      QuestLocation.kitchen => Icons.kitchen_rounded,
      QuestLocation.bedroom => Icons.bed_rounded,
      QuestLocation.study => Icons.menu_book_rounded,
      QuestLocation.outdoor => Icons.park_rounded,
      QuestLocation.other => Icons.home_rounded,
    };
