import 'package:flutter/material.dart';

/// How one cosmetic looks, and the level that unlocks it.
///
/// Shaped like AvatarStyle and BadgeStyle: each registry (outfits, headwear,
/// pets, room items) maps the key the server stores to one of these, so art,
/// names and levels can change without a migration.
///
/// Until the drawn art arrives, every item shows a placeholder: an emoji on a
/// colour, or just the colour. Setting [asset] swaps in the real picture, and
/// nothing that uses the registry has to change.
class CosmeticStyle {
  const CosmeticStyle({
    required this.title,
    required this.background,
    this.emoji,
    this.asset,
    this.unlockLevel = 1,
  });

  final String title;

  /// Placeholder colour, and the tint behind a transparent picture.
  final Color background;

  /// Placeholder picture. Emoji from Unicode 6, which every Android version
  /// the study includes can draw; null for a plain colour swatch.
  final String? emoji;

  /// A transparent PNG under assets/cosmetics/, once drawn. Null until then.
  final String? asset;

  /// The level a child must reach to unlock it. Levels come from
  /// lib/shared/leveling.dart; 1 means from the start.
  final int unlockLevel;

  bool unlockedAt(int level) => unlockLevel <= level;
}

/// A cosmetic's picture: the drawn asset when there is one, otherwise its
/// placeholder.
class CosmeticArt extends StatelessWidget {
  const CosmeticArt(this.style, {super.key, this.size = 64});

  final CosmeticStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = style.asset;
    final emoji = style.emoji;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: asset != null
          ? Image.asset(asset, width: size * 0.9, height: size * 0.9)
          : emoji != null
              ? ExcludeSemantics(
                  child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
                )
              : null,
    );
  }
}
