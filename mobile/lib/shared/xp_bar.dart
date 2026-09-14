import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'leveling.dart';

/// How far a child is towards their next level.
///
/// Fills between the XP where the current level began and the XP where the
/// next one begins, both from [levelFor], so it can never disagree with the
/// level label. When XP changes it animates: going up a level, the bar first
/// fills to the end and then starts again from empty, so a level-up reads as
/// finishing a bar rather than losing progress.
class XpBar extends StatefulWidget {
  const XpBar({
    super.key,
    required this.xp,
    this.height = 14,
    this.color,
    this.backgroundColor,
  });

  final int xp;
  final double height;
  final Color? color;
  final Color? backgroundColor;

  @override
  State<XpBar> createState() => _XpBarState();
}

class _XpBarState extends State<XpBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// What the bar shows when nothing is animating.
  late Animation<double> _value = AlwaysStoppedAnimation(
    levelFor(widget.xp).fraction,
  );

  @override
  void didUpdateWidget(XpBar old) {
    super.didUpdateWidget(old);
    if (old.xp == widget.xp) return;

    final from = _value.value;
    final before = levelFor(old.xp);
    final after = levelFor(widget.xp);

    final Animatable<double> path;
    if (after.level > before.level) {
      // Finish this bar, then start the new level's bar from empty.
      path = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: from, end: 1.0),
          weight: math.max(1.0 - from, 0.1),
        ),
        TweenSequenceItem(
          tween: Tween(begin: 0.0, end: after.fraction),
          weight: math.max(after.fraction, 0.1),
        ),
      ]);
    } else {
      // Within a level, or down one after a grown-up changed an approval.
      path = Tween(begin: from, end: after.fraction);
    }

    _value = path.animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    // Someone who has turned animations off still sees the bar change, just
    // without the movement.
    _controller.duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 900);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = levelFor(widget.xp);

    return AnimatedBuilder(
      animation: _value,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.height / 2),
        child: LinearProgressIndicator(
          value: _value.value,
          minHeight: widget.height,
          color: widget.color ?? scheme.primary,
          backgroundColor:
              widget.backgroundColor ?? scheme.surfaceContainerHighest,
          // A progress bar's spoken value must be a number from 0 to 100; the
          // words go in the label.
          semanticsLabel:
              'Level ${progress.level}: ${progress.xpIntoLevel} '
              'of ${progress.xpForLevel} XP to level ${progress.level + 1}',
          semanticsValue: '${(progress.fraction * 100).round()}',
        ),
      ),
    );
  }
}
