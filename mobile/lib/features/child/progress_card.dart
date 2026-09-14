import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_progress.dart';
import '../../shared/avatars.dart';
import '../../shared/leveling.dart';
import '../../shared/xp_bar.dart';

/// The child's avatar and how far they have come: level, XP, the bar towards
/// the next level, and their streak.
///
/// Game progress only. Screen time is counted by the ledger and shown on its
/// own card; nothing here changes it.
class ProgressCard extends StatelessWidget {
  const ProgressCard({
    super.key,
    required this.avatar,
    required this.progress,
    this.onTap,
  });

  final String avatar;
  final AsyncValue<ChildProgress> progress;

  /// Opens the quest log when set, and the card says so.
  final VoidCallback? onTap;

  static const gold = Color(0xFFFFF1C2);
  static const ink = Color(0xFF6E5200);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = progress.hasValue ? progress.requireValue : null;
    // Worked out on every build, so the label changes the moment a refresh
    // brings XP over a threshold.
    final level = value == null ? null : levelFor(value.xp);
    final open = onTap;

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AvatarBadge(avatar, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level == null ? 'Level ...' : 'Level ${level.level}',
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 22,
                          color: Color(0xFFE0A100),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            value == null ? '...' : '${value.xp} XP',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (value != null)
                _StreakBadge(
                  days: value.currentStreak,
                  todayCounted: value.todayCounted,
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Built only once XP has loaded, so opening the screen does not
          // play a level-up from zero.
          if (value != null && level != null) ...[
            XpBar(xp: value.xp, backgroundColor: Colors.white),
            const SizedBox(height: 6),
            Text(
              '${level.xpToNextLevel} XP to level ${level.level + 1}',
              style: text.bodyMedium?.copyWith(color: ink),
            ),
            if (value.currentStreak > 0 && !value.todayCounted)
              Text(
                'Finish a quest today to keep your streak going!',
                style: text.bodyMedium?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ] else
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: const LinearProgressIndicator(
                value: 0,
                minHeight: 14,
                backgroundColor: Colors.white,
              ),
            ),
          if (open != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.emoji_events_rounded, size: 22, color: ink),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'My quest log',
                    style: text.labelLarge?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: ink),
              ],
            ),
          ],
        ],
      ),
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: gold,
      clipBehavior: Clip.antiAlias,
      child: open == null
          ? content
          : MergeSemantics(child: InkWell(onTap: open, child: content)),
    );
  }
}

/// Days in a row with an approved quest, as a flame and a number. The flame
/// is filled once today's quest is approved, and hollow while the streak is
/// still waiting for today's.
class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days, required this.todayCounted});

  final int days;
  final bool todayCounted;

  static const _flame = Color(0xFFD9480F);
  static const _cold = Color(0xFF7D6A3C);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final alive = days > 0;

    return Semantics(
      label: days == 1 ? 'Streak: 1 day in a row' : 'Streak: $days days in a row',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                alive && todayCounted
                    ? Icons.local_fire_department
                    : Icons.local_fire_department_outlined,
                size: 34,
                color: alive ? _flame : _cold,
              ),
              Text(
                '$days',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ProgressCard.ink,
                ),
              ),
              Text(
                days == 1 ? 'day' : 'days',
                style: text.labelMedium?.copyWith(color: ProgressCard.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
