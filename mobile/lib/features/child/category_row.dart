import 'package:flutter/material.dart';

import '../../core/models/cosmetics.dart';
import '../../shared/cosmetic_tile.dart';
import '../../shared/cosmetics.dart';
import 'wardrobe.dart';

/// One category's items in a row, worn, open and locked alike.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.category,
    required this.level,
    required this.wardrobe,
    required this.busy,
    required this.onWear,
  });

  final CosmeticCategory category;
  final int level;
  final Wardrobe? wardrobe;
  final String? busy;
  final ValueChanged<String> onWear;

  @override
  Widget build(BuildContext context) {
    final items = cosmeticsIn(category);
    final worn = wardrobe;
    final wearing = worn == null ? defaultKeyFor(category) : wornIn(worn, category);

    return SizedBox(
      height: 140,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final entry in items.entries)
            CosmeticTile(
              style: entry.value,
              state: entry.key == wearing
                  ? TileState.worn
                  : entry.value.unlockedAt(level) || (worn?.owns(category, entry.key) ?? false)
                      ? TileState.open
                      : TileState.locked,
              busy: busy == '${category.name}:${entry.key}',
              onTap: () => onWear(entry.key),
            ),
        ],
      ),
    );
  }
}
