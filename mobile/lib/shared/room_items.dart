import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// The fixed places in a child's room where an item can go. The room is one
/// illustrated scene with these slots, not a free-roam tile map.
enum RoomSlot {
  rug,
  wall,
  plant;

  String get label => switch (this) {
        rug => 'Rug',
        wall => 'Wall art',
        plant => 'Plant',
      };
}

/// A room item: a cosmetic that belongs in one [slot].
class RoomItemStyle extends CosmeticStyle {
  const RoomItemStyle({
    required this.slot,
    required super.title,
    required super.background,
    super.emoji,
    super.asset,
    super.unlockLevel,
  });

  final RoomSlot slot;
}

/// Everything that can go in a child's room, keyed as the server stores it,
/// grouped by slot and ordered from the start of each slot's list.
///
/// Names are the Phase 3 plan's; the emoji are placeholders drawn on the
/// item's colour until the room art (A2/L1) arrives.
const roomItems = <String, RoomItemStyle>{
  // ---- rugs ----
  'rug_star': RoomItemStyle(
    slot: RoomSlot.rug,
    title: 'Star Rug',
    asset: 'assets/cosmetics/rugs/rug_star.png',
    emoji: '⭐',
    background: Color(0xFFEBDCCB),
  ),
  'rug_rainbow': RoomItemStyle(
    slot: RoomSlot.rug,
    title: 'Rainbow Rug',
    asset: 'assets/cosmetics/rugs/rug_rainbow.png',
    emoji: '🌈',
    background: Color(0xFFF7DEE9),
    unlockLevel: 2,
  ),
  'rug_jungle': RoomItemStyle(
    slot: RoomSlot.rug,
    title: 'Jungle Rug',
    asset: 'assets/cosmetics/rugs/rug_jungle.png',
    emoji: '🌿',
    background: Color(0xFFB9DFA2),
    unlockLevel: 4,
  ),
  'rug_ocean': RoomItemStyle(
    slot: RoomSlot.rug,
    title: 'Ocean Wave Rug',
    asset: 'assets/cosmetics/rugs/rug_ocean.png',
    emoji: '🌊',
    background: Color(0xFF9CC3E6),
    unlockLevel: 6,
  ),

  // ---- wall art ----
  'wall_sun': RoomItemStyle(
    slot: RoomSlot.wall,
    title: 'Cheerful Sun Painting',
    asset: 'assets/cosmetics/wall/wall_sun.png',
    emoji: '🌞',
    background: Color(0xFFFFF1C2),
  ),
  'wall_map': RoomItemStyle(
    slot: RoomSlot.wall,
    title: 'Adventure Map',
    asset: 'assets/cosmetics/wall/wall_map.png',
    emoji: '📜',
    background: Color(0xFFFFE3CC),
    unlockLevel: 2,
  ),
  'wall_superhero': RoomItemStyle(
    slot: RoomSlot.wall,
    title: 'Superhero Poster',
    asset: 'assets/cosmetics/wall/wall_superhero.png',
    emoji: '⚡',
    background: Color(0xFFF7DEE9),
    unlockLevel: 3,
  ),
  'wall_space': RoomItemStyle(
    slot: RoomSlot.wall,
    title: 'Space Poster',
    asset: 'assets/cosmetics/wall/wall_space.png',
    emoji: '🚀',
    background: Color(0xFFD5E6F5),
    unlockLevel: 5,
  ),

  // ---- plants ----
  'plant_daisy': RoomItemStyle(
    slot: RoomSlot.plant,
    title: 'Blooming Daisy',
    asset: 'assets/cosmetics/plants/plant_daisy.png',
    emoji: '🌼',
    background: Color(0xFFD9F0CB),
  ),
  'plant_cactus': RoomItemStyle(
    slot: RoomSlot.plant,
    title: 'Cactus Buddy',
    asset: 'assets/cosmetics/plants/plant_cactus.png',
    emoji: '🌵',
    background: Color(0xFFD7F0C9),
    unlockLevel: 2,
  ),
  'plant_sunflower': RoomItemStyle(
    slot: RoomSlot.plant,
    title: 'Sunny Sunflower',
    asset: 'assets/cosmetics/plants/plant_sunflower.png',
    emoji: '🌻',
    background: Color(0xFFFFE7B8),
    unlockLevel: 4,
  ),
  'plant_bonsai': RoomItemStyle(
    slot: RoomSlot.plant,
    title: 'Tiny Bonsai',
    asset: 'assets/cosmetics/plants/plant_bonsai.png',
    emoji: '🌳',
    background: Color(0xFFCFE8C0),
    unlockLevel: 6,
  ),
};

/// What each slot holds until a child chooses something else.
const defaultRoomItems = <RoomSlot, String>{
  RoomSlot.rug: 'rug_star',
  RoomSlot.wall: 'wall_sun',
  RoomSlot.plant: 'plant_daisy',
};

/// The items that fit [slot], in the registry's order.
Map<String, RoomItemStyle> roomItemsIn(RoomSlot slot) => {
      for (final entry in roomItems.entries)
        if (entry.value.slot == slot) entry.key: entry.value,
    };

/// The item for [key] in [slot], or that slot's default for a key this
/// version does not know or that belongs to a different slot.
RoomItemStyle roomItemFor(RoomSlot slot, String key) {
  final item = roomItems[key];
  return item != null && item.slot == slot
      ? item
      : roomItems[defaultRoomItems[slot]]!;
}
