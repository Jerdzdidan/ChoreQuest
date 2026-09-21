import 'package:flutter/material.dart';

import '../../core/models/chore.dart';
import '../../shared/quest_places.dart';
import '../../shared/theme.dart';
import 'child_providers.dart';

/// Today's quests at one place on the map, and how many of them are done.
class PlaceTally {
  const PlaceTally({required this.place, required this.quests, required this.done});

  final QuestLocation place;
  final int quests;
  final int done;

  bool get empty => quests == 0;
  bool get allDone => quests > 0 && done == quests;
}

/// Today's quests counted by place, in map order.
///
/// The four places always appear, so the map keeps its shape. "Other" appears
/// only when a quest has no place set: such a quest is never lost from the
/// map, and there is never an empty stop for it. Pure, like the allocation
/// engine: the same quests and states always give the same tallies.
List<PlaceTally> tallyByPlace(List<Assignment> quests, ChoreState Function(Assignment) stateOf) => [
      for (final place in QuestLocation.values)
        if (place != QuestLocation.other || quests.any((q) => q.location == place))
          PlaceTally(
            place: place,
            quests: quests.where((q) => q.location == place).length,
            done: quests.where((q) => q.location == place && stateOf(q) == ChoreState.done).length,
          ),
    ];

/// The quest map: the places in the home as stops along a trail, each with
/// how many of today's quests there are done. Tapping a place opens its
/// quests; a place with none today rests, faded, and does nothing.
///
/// Drawn in the theme's colours with the place icons until the map art (A3)
/// arrives. The stops, counts and taps stay the same when it does.
class QuestMap extends StatelessWidget {
  const QuestMap({super.key, required this.tallies, required this.onOpen});

  final List<PlaceTally> tallies;
  final ValueChanged<QuestLocation> onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: QuestColors.of(context).map.ground,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final (i, tally) in tallies.indexed)
              _MapStop(
                tally: tally,
                onLeft: i.isEven,
                trailAbove: i > 0,
                trailBelow: i < tallies.length - 1,
                onOpen: () => onOpen(tally.place),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a screen reader says for one stop.
String describeStop(PlaceTally tally) {
  final place = tally.place.label;
  if (tally.empty) return '$place: no quests today';
  if (tally.allDone) return '$place: all done today!';
  final quests = tally.quests == 1 ? 'quest' : 'quests';
  return '$place: ${tally.done} of ${tally.quests} $quests done today';
}

class _MapStop extends StatelessWidget {
  const _MapStop({
    required this.tally,
    required this.onLeft,
    required this.trailAbove,
    required this.trailBelow,
    required this.onOpen,
  });

  final PlaceTally tally;
  final bool onLeft;
  final bool trailAbove;
  final bool trailBelow;
  final VoidCallback onOpen;

  static const _node = 84.0;
  static const _inset = 16.0;

  @override
  Widget build(BuildContext context) {
    final colors = QuestColors.of(context);
    final tint = colors.place(tally.place);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final open = tally.empty ? null : onOpen;

    final node = _PlaceNode(tally: tally, size: _node);
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: onLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(
          tally.place.label,
          textAlign: onLeft ? TextAlign.start : TextAlign.end,
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: tally.empty ? scheme.onSurfaceVariant : tint.ink,
          ),
        ),
        const SizedBox(height: 4),
        _Count(tally: tally),
      ],
    );

    return Semantics(
      button: open != null,
      onTap: open,
      label: describeStop(tally),
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _TrailPainter(
            centreFromSide: _inset + _node / 2,
            onLeft: onLeft,
            above: trailAbove,
            below: trailBelow,
            colour: colors.map.trail,
          ),
          child: InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _inset, vertical: 12),
              child: Row(
                children: onLeft
                    ? [node, const SizedBox(width: 14), Expanded(child: label)]
                    : [Expanded(child: label), const SizedBox(width: 14), node],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A place's round badge: its icon on its colour, faded when there is nothing
/// to do there today, with a tick once everything there is done.
class _PlaceNode extends StatelessWidget {
  const _PlaceNode({required this.tally, required this.size});

  final PlaceTally tally;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = QuestColors.of(context);
    final tint = colors.place(tally.place);

    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // A faded badge still hides the trail running into it.
          if (tally.empty)
            DecoratedBox(
              decoration: BoxDecoration(color: colors.map.ground, shape: BoxShape.circle),
            ),
          Opacity(
            opacity: tally.empty ? 0.45 : 1,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.fill,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: tally.empty
                    ? null
                    : [
                        BoxShadow(
                          color: tint.ink.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Icon(iconForLocation(tally.place), size: size * 0.48, color: tint.ink),
            ),
          ),
          if (tally.allDone)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.done,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// "1/3 done", "All done!" or "Nothing today" under a place's name.
class _Count extends StatelessWidget {
  const _Count({required this.tally});

  final PlaceTally tally;

  @override
  Widget build(BuildContext context) {
    final colors = QuestColors.of(context);
    final text = Theme.of(context).textTheme;

    if (tally.empty) {
      return Text(
        'Nothing today',
        style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }

    final (label, icon, fill, ink) = tally.allDone
        ? ('All done!', Icons.check_rounded, colors.done, Colors.white)
        : ('${tally.done}/${tally.quests} done', Icons.flag_rounded, Colors.white, colors.place(tally.place).ink);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(color: ink, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// The trail through one stop: in from the middle of the stop above, round
/// through this stop's badge, and out to the middle of the stop below. Every
/// stop meets its neighbours at the middle, so the trail runs unbroken however
/// tall large text makes a stop.
class _TrailPainter extends CustomPainter {
  const _TrailPainter({
    required this.centreFromSide,
    required this.onLeft,
    required this.above,
    required this.below,
    required this.colour,
  });

  /// How far the badge's centre sits from its side of the map.
  final double centreFromSide;
  final bool onLeft;
  final bool above;
  final bool below;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (!above && !below) return;

    final centre = Offset(onLeft ? centreFromSide : size.width - centreFromSide, size.height / 2);
    final middle = size.width / 2;
    final path = Path();
    if (above) {
      final bend = centre.dy / 2;
      path
        ..moveTo(middle, 0)
        ..cubicTo(middle, bend, centre.dx, bend, centre.dx, centre.dy);
    } else {
      path.moveTo(centre.dx, centre.dy);
    }
    if (below) {
      final bend = centre.dy + (size.height - centre.dy) / 2;
      path.cubicTo(centre.dx, bend, middle, bend, middle, size.height);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round,
    );

    // Footsteps down the middle of the trail.
    final steps = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var at = 4.0; at < metric.length; at += 16) {
        canvas.drawPath(metric.extractPath(at, at + 7), steps);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.centreFromSide != centreFromSide ||
      old.onLeft != onLeft ||
      old.above != above ||
      old.below != below ||
      old.colour != colour;
}
