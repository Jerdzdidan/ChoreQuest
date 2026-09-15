/// What a cosmetic slots into. One item of each can be on at a time, and the
/// name is what the server stores. Each room slot is its own category, so a
/// rug, a picture and a plant can all be on at once.
enum CosmeticCategory {
  outfit,
  headwear,
  pet,
  rug,
  wall,
  plant;

  /// Null for a category this version of the app does not know.
  static CosmeticCategory? parse(String? raw) {
    for (final category in values) {
      if (category.name == raw) return category;
    }
    return null;
  }
}

/// One cosmetic a child has unlocked.
class OwnedCosmetic {
  const OwnedCosmetic({
    required this.category,
    required this.key,
    required this.unlockedAt,
    required this.equipped,
  });

  final CosmeticCategory category;

  /// The registry key, such as `space_suit`.
  final String key;
  final DateTime unlockedAt;

  /// Whether the child has it on. At most one per category.
  final bool equipped;
}

/// Everything a child has unlocked, as the server records it.
class Wardrobe {
  const Wardrobe(this.items);

  factory Wardrobe.fromJson(Map<String, dynamic> json) => Wardrobe([
        for (final raw in (json['cosmetics'] as List? ?? const [])
            .cast<Map<String, dynamic>>())
          if (CosmeticCategory.parse(raw['category'] as String?)
              case final category?)
            OwnedCosmetic(
              category: category,
              key: raw['key'] as String,
              unlockedAt: DateTime.parse(raw['unlocked_at'] as String),
              equipped: raw['equipped'] as bool? ?? false,
            ),
      ]);

  final List<OwnedCosmetic> items;

  bool owns(CosmeticCategory category, String key) =>
      items.any((item) => item.category == category && item.key == key);

  /// The key of the item on in [category], or null when nothing has been
  /// chosen, which means the registry's default.
  String? equippedIn(CosmeticCategory category) {
    for (final item in items) {
      if (item.category == category && item.equipped) return item.key;
    }
    return null;
  }
}
