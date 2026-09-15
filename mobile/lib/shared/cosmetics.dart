import '../core/models/cosmetics.dart';
import 'cosmetic_style.dart';
import 'headwear.dart';
import 'outfits.dart';
import 'pets.dart';
import 'room_items.dart';

/// Every cosmetic registry, reached by category.
///
/// The registries hold the unlock levels, beside the level thresholds in
/// leveling.dart; this puts them side by side so the app can work out
/// everything a level unlocks in one place.
Map<String, CosmeticStyle> cosmeticsIn(CosmeticCategory category) =>
    switch (category) {
      CosmeticCategory.outfit => outfits,
      CosmeticCategory.headwear => headwear,
      CosmeticCategory.pet => pets,
      CosmeticCategory.rug => roomItemsIn(RoomSlot.rug),
      CosmeticCategory.wall => roomItemsIn(RoomSlot.wall),
      CosmeticCategory.plant => roomItemsIn(RoomSlot.plant),
    };

/// Every item a child at [level] has unlocked, across all categories, in
/// registry order. Deterministic: the same level always unlocks the same
/// items.
List<(CosmeticCategory, String)> cosmeticsUnlockedAt(int level) => [
      for (final category in CosmeticCategory.values)
        for (final entry in cosmeticsIn(category).entries)
          if (entry.value.unlockedAt(level)) (category, entry.key),
    ];

/// What a child at [level] has unlocked that [wardrobe] does not hold yet.
///
/// Never anything to take away: an item recorded at a higher level, or under
/// an older, lower threshold, stays in the wardrobe.
List<(CosmeticCategory, String)> unlocksToRecord(int level, Wardrobe wardrobe) => [
      for (final (category, key) in cosmeticsUnlockedAt(level))
        if (!wardrobe.owns(category, key)) (category, key),
    ];
