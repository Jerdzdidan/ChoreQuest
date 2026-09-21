import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// Where an item stands for this child.
enum TileState {
  /// Being worn now.
  worn,

  /// Unlocked, and can be put on.
  open,

  /// Needs a higher level.
  locked,
}

/// One cosmetic to pick: its picture and name, a ring when it is worn, and
/// the same lock and "Level N" the animal picker (G10) uses when it is not
/// yet unlocked.
class CosmeticTile extends StatelessWidget {
  const CosmeticTile({
    super.key,
    required this.style,
    required this.state,
    required this.onTap,
    this.busy = false,
  });

  final CosmeticStyle style;
  final TileState state;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final worn = state == TileState.worn;
    final locked = state == TileState.locked;

    return Semantics(
      button: !locked && !worn,
      selected: worn,
      enabled: !locked,
      label: locked
          ? '${style.title}. Unlocks at level ${style.unlockLevel}.'
          : worn
              ? '${style.title}. Wearing it.'
              : style.title,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 92,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: locked || worn || busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              // The label takes whatever height is left and shortens with an
              // ellipsis, so large text never pushes the tile past its row.
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: worn ? scheme.primary : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: Opacity(
                          opacity: locked ? 0.4 : 1,
                          child: CosmeticArt(style, size: 64),
                        ),
                      ),
                      if (locked)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: scheme.inverseSurface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.lock_rounded, size: 14, color: scheme.onInverseSurface),
                          ),
                        ),
                      if (worn)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Icon(Icons.check_circle_rounded, size: 22, color: scheme.primary),
                        ),
                      if (busy)
                        const SizedBox.square(
                          dimension: 32,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      locked ? 'Level ${style.unlockLevel}' : style.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: text.labelMedium?.copyWith(
                        fontWeight: worn ? FontWeight.w700 : FontWeight.w500,
                        color: locked ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
