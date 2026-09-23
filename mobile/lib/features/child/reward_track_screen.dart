import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_progress.dart';
import '../../core/models/cosmetics.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/async_view.dart';
import '../../shared/avatars.dart';
import '../../shared/leveling.dart';
import '../../shared/reward_track.dart';
import '../../shared/theme.dart';
import '../../shared/xp_bar.dart';
import 'child_providers.dart';
import 'wardrobe.dart';

/// The Reward Track: every level and what reaching it unlocks, with ticks on
/// the levels behind the child, a "you are here" marker at their level and
/// locks on the levels ahead (T2). Above it, the last few things the child
/// earned (RW2); below it, the badges and story chapters, which open at
/// milestones rather than at a level.
///
/// A preview only. Nothing here can be bought, tapped to skip ahead or won by
/// chance: every reward is earned by doing quests, like every other reward in
/// the app.
class RewardTrackScreen extends ConsumerWidget {
  const RewardTrackScreen({super.key, this.showAppBar = true});

  /// False when the screen is the Rewards tab, under the shell's own bar.
  final bool showAppBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ChildSession s) => s,
      _ => null,
    };
    if (me == null) return const SizedBox.shrink();

    final progress = ref.watch(progressProvider);
    // Only for when each cosmetic was unlocked. Without it, the strip still
    // shows badges and chapters.
    final wardrobe = ref.watch(wardrobeProvider).value;

    final body = RefreshIndicator(
      onRefresh: () => ref.refresh(progressProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AsyncView<ChildProgress>(
            value: progress,
            onRetry: () => ref.invalidate(progressProvider),
            builder: (context, p) => _Track(progress: p, wardrobe: wardrobe, avatar: me.avatar),
          ),
        ],
      ),
    );

    if (!showAppBar) return body;
    return Scaffold(appBar: AppBar(title: const Text('Reward track')), body: body);
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.progress, required this.wardrobe, required this.avatar});

  final ChildProgress progress;
  final Wardrobe? wardrobe;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final here = levelFor(progress.xp);
    final recent = recentlyEarned(progress, wardrobe);
    final levels = rewardTrack();
    final behind = [for (final stop in levels) if (stop.level <= here.level) stop];
    final ahead = [for (final stop in levels) if (stop.level > here.level) stop];
    final lit = scheme.primary;
    final dim = scheme.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recent.isNotEmpty) ...[
          _RecentStrip(rewards: recent, today: progress.today),
          const SizedBox(height: 24),
        ],
        Text('What every level unlocks', style: text.titleLarge),
        const SizedBox(height: 12),
        for (final (i, stop) in behind.indexed)
          _LevelStop(stop: stop, xp: progress.xp, reached: true, lineAbove: i > 0 ? lit : null, lineBelow: lit),
        _YouAreHere(here: here, avatar: avatar, allUnlocked: ahead.isEmpty, lineAbove: lit, lineBelow: ahead.isEmpty ? null : dim),
        for (final (i, stop) in ahead.indexed)
          _LevelStop(
            stop: stop,
            xp: progress.xp,
            reached: false,
            lineAbove: dim,
            lineBelow: i < ahead.length - 1 ? dim : null,
          ),
        const SizedBox(height: 24),
        Text('Badges and story', style: text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'These open by doing quests, whatever your level.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _MilestoneList(milestones: milestoneTrack(progress)),
      ],
    );
  }
}

/// The last one to three things earned (RW2). Not shown at all for a child
/// who has not earned anything yet.
class _RecentStrip extends StatelessWidget {
  const _RecentStrip({required this.rewards, required this.today});

  final List<RecentReward> rewards;

  /// The server's today, which follows the household's timezone (TZ3).
  final DateTime today;

  String _when(BuildContext context, DateTime at) {
    final day = DateUtils.dateOnly(at.toLocal());
    final days = DateUtils.dateOnly(today).difference(day).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return MaterialLocalizations.of(context).formatShortMonthDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final xp = QuestColors.of(context).xp;

    return Card(
      margin: EdgeInsets.zero,
      color: xp.fill,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.celebration_rounded, color: xp.ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recently earned',
                    style: text.titleMedium?.copyWith(color: xp.ink, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final reward in rewards)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MergeSemantics(
                  child: Row(
                    children: [
                      _RewardPicture(
                        background: reward.background,
                        ink: reward.ink,
                        icon: reward.icon,
                        emoji: reward.emoji,
                        asset: reward.asset,
                        tinted: reward.tinted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reward.title,
                              style: text.titleSmall?.copyWith(color: xp.ink, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${reward.kind} · ${_when(context, reward.at)}',
                              style: text.bodySmall?.copyWith(color: xp.ink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One level on the track and what it unlocks, with the rail running through
/// its marker: a tick once reached, a lock while still ahead.
class _LevelStop extends StatelessWidget {
  const _LevelStop({
    required this.stop,
    required this.xp,
    required this.reached,
    required this.lineAbove,
    required this.lineBelow,
  });

  final TrackLevel stop;
  final int xp;
  final bool reached;
  final Color? lineAbove;
  final Color? lineBelow;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final done = QuestColors.of(context).done;

    final (tag, tagIcon, tagColour) = reached
        ? (stop.level == 1 ? 'From the start' : 'Unlocked', Icons.check_circle_rounded, done)
        : ('${xpToReach(stop.level) - xp} XP to go', Icons.lock_rounded, scheme.onSurfaceVariant);

    return _Rail(
      above: lineAbove,
      below: lineBelow,
      marker: reached
          ? CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primary,
              child: Icon(Icons.check_rounded, color: scheme.onPrimary, size: 22),
            )
          : Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant, width: 2),
              ),
              child: Icon(Icons.lock_rounded, color: scheme.outline, size: 18),
            ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: reached ? 1 : 0,
        color: reached ? null : scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text('Level ${stop.level}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tagIcon, size: 18, color: tagColour),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          tag,
                          style: text.labelLarge?.copyWith(color: tagColour, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final reward in stop.rewards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MergeSemantics(
                    child: Row(
                      children: [
                        _RewardPicture(
                          background: reward.background,
                          emoji: reward.emoji,
                          asset: reward.asset,
                          faded: !reached,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(reward.title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              Text(
                                reward.kind,
                                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The child on the track: their animal on the rail, their level, and how
/// far it is to the next.
class _YouAreHere extends StatelessWidget {
  const _YouAreHere({
    required this.here,
    required this.avatar,
    required this.allUnlocked,
    required this.lineAbove,
    required this.lineBelow,
  });

  final LevelProgress here;
  final String avatar;

  /// Past the last level with anything to unlock.
  final bool allUnlocked;
  final Color? lineAbove;
  final Color? lineBelow;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final xp = QuestColors.of(context).xp;
    final scheme = Theme.of(context).colorScheme;

    return _Rail(
      above: lineAbove,
      below: lineBelow,
      markerSize: 48,
      marker: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 3),
        ),
        child: AvatarBadge(avatar, size: 42),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        color: xp.fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: xp.ink.withValues(alpha: 0.35), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are here',
                  style: text.labelLarge?.copyWith(color: xp.ink, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Level ${here.level}',
                  style: text.headlineSmall?.copyWith(color: xp.ink, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                XpBar(xp: here.xp),
                const SizedBox(height: 6),
                Text(
                  allUnlocked
                      ? 'You have unlocked everything on the track!'
                      : '${here.xpToNextLevel} XP to level ${here.level + 1}',
                  style: text.bodyMedium?.copyWith(color: xp.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of the track: a marker on the vertical rail, and a card beside it.
/// The rail is painted per row and meets the next row's at the row's edge,
/// so it runs unbroken however tall large text makes a card.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.marker,
    required this.child,
    required this.above,
    required this.below,
    this.markerSize = 36,
  });

  final Widget marker;
  final Widget child;
  final Color? above;
  final Color? below;
  final double markerSize;

  static const _railWidth = 48.0;
  static const _markerTop = 8.0;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RailPainter(
        x: _railWidth / 2,
        y: _markerTop + markerSize / 2,
        above: above,
        below: below,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _railWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: _markerTop),
                child: Center(
                  child: ExcludeSemantics(
                    child: SizedBox.square(dimension: markerSize, child: marker),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter({required this.x, required this.y, required this.above, required this.below});

  final double x;

  /// Where the marker's centre sits, down from the top of the row.
  final double y;
  final Color? above;
  final Color? below;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.butt;
    final above = this.above;
    final below = this.below;
    if (above != null) canvas.drawLine(Offset(x, 0), Offset(x, y), paint..color = above);
    if (below != null) canvas.drawLine(Offset(x, y), Offset(x, size.height), paint..color = below);
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.x != x || old.y != y || old.above != above || old.below != below;
}

/// Badges and story chapters, earned ones first, six at a time like every
/// badge list (V2).
class _MilestoneList extends StatefulWidget {
  const _MilestoneList({required this.milestones});

  final List<MilestoneReward> milestones;

  @override
  State<_MilestoneList> createState() => _MilestoneListState();
}

class _MilestoneListState extends State<_MilestoneList> {
  static const _shownAtFirst = 6;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final done = QuestColors.of(context).done;
    final all = widget.milestones;
    final hidden = all.length - _shownAtFirst;
    final shown = _showAll ? all : all.take(_shownAtFirst);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final milestone in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MergeSemantics(
              child: Row(
                children: [
                  _RewardPicture(
                    background: milestone.background,
                    ink: milestone.ink,
                    icon: milestone.icon,
                    emoji: milestone.emoji,
                    asset: milestone.asset,
                    tinted: milestone.tinted,
                    faded: !milestone.earned,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(milestone.title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          milestone.earned ? '${milestone.kind} · Earned' : '${milestone.kind} · ${milestone.howToEarn}',
                          style: text.bodySmall?.copyWith(
                            color: milestone.earned ? done : scheme.onSurfaceVariant,
                            fontWeight: milestone.earned ? FontWeight.w700 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (milestone.earned)
                    Icon(Icons.check_circle_rounded, color: done)
                  else
                    Icon(Icons.lock_rounded, color: scheme.outline, size: 20),
                ],
              ),
            ),
          ),
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(_showAll ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
              label: Text(_showAll ? 'See fewer' : 'See more ($hidden)'),
            ),
          ),
      ],
    );
  }
}

/// A reward's picture: its drawn asset once there is one, otherwise its icon
/// or placeholder emoji on its colour. Pale while still locked.
class _RewardPicture extends StatelessWidget {
  const _RewardPicture({
    required this.background,
    this.ink,
    this.icon,
    this.emoji,
    this.asset,
    this.tinted = false,
    this.faded = false,
  });

  final Color background;
  final Color? ink;
  final IconData? icon;
  final String? emoji;
  final String? asset;

  /// Whether the drawing is black on transparent and takes [ink], as the
  /// badges do, rather than a picture in its own colours.
  final bool tinted;
  final bool faded;

  static const _size = 44.0;

  @override
  Widget build(BuildContext context) {
    final asset = this.asset;
    final icon = this.icon;
    final emoji = this.emoji;

    final picture = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_size * 0.25),
      ),
      child: asset != null
          ? Image.asset(
              asset,
              width: _size * 0.85,
              height: _size * 0.85,
              filterQuality: FilterQuality.none,
              color: tinted ? ink : null,
              colorBlendMode: tinted ? BlendMode.srcIn : BlendMode.dst,
            )
          : icon != null
              ? Icon(icon, size: _size * 0.55, color: ink)
              : emoji != null
                  ? Text(emoji, style: const TextStyle(fontSize: _size * 0.5))
                  : null,
    );

    return ExcludeSemantics(
      child: faded ? Opacity(opacity: 0.5, child: picture) : picture,
    );
  }
}
