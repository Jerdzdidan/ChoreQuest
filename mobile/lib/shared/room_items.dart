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
/// Rugs are plain colour swatches until the art arrives, since no Unicode 6
/// emoji draws a rug. Titles, levels and placeholders are a starting set for
/// the art team to replace (A2).
const roomItems = <String, RoomItemStyle>{
  // ---- rugs ----
  'rug_sand': RoomItemStyle(
    slot: RoomSlot.rug,
    title: 'Sand rug',
    background: Color(0xFFEBDCCB),
  ),
  'rug_ocean': RoomItemStyle(
    slot: RoomSlot.rug,
    title: 'Ocean rug',
    background: Color(0xFF9CC3E6),
    unlockLevel: 2,
  ),
  'rug_meadow': RoomItemStyle(
    slot: RoomSlot.rug,
    title: 'Meadow rug',
    background: Color(0xFFB9DFA2),
    unlockLevel: 4,
  ),
  'rug_sunset': RoomItemStyle(
    slot: RoomSlot.rug,
    title: 'Sunset rug',
    background: Color(0xFFFFB38A),
    unlockLevel: 6,
  ),

  // ---- wall art ----
  'wall_clock': RoomItemStyle(
    slot: RoomSlot.wall,
    title: 'Clock',
    emoji: '🕒',
    background: Color(0xFFE4E7EA),
  ),
  'wall_rainbow': RoomItemStyle(
    slot: RoomSlot.wall,
    title: 'Rainbow picture',
    emoji: '🌈',
    background: Color(0xFFF7DEE9),
    unlockLevel: 2,
  ),
  'wall_rocket': RoomItemStyle(
    slot: RoomSlot.wall,
    title: 'Rocket poster',
    emoji: '🚀',
    background: Color(0xFFD5E6F5),
    unlockLevel: 3,
  ),
  'wall_star': RoomItemStyle(
    slot: RoomSlot.wall,
    title: 'Gold star',
    emoji: '⭐',
    background: Color(0xFFFFF1C2),
    unlockLevel: 5,
  ),

  // ---- plants ----
  'plant_seedling': RoomItemStyle(
    slot: RoomSlot.plant,
    title: 'Seedling',
    emoji: '🌱',
    background: Color(0xFFD9F0CB),
  ),
  'plant_cactus': RoomItemStyle(
    slot: RoomSlot.plant,
    title: 'Cactus',
    emoji: '🌵',
    background: Color(0xFFD7F0C9),
    unlockLevel: 2,
  ),
  'plant_sunflower': RoomItemStyle(
    slot: RoomSlot.plant,
    title: 'Sunflower',
    emoji: '🌻',
    background: Color(0xFFFFE7B8),
    unlockLevel: 4,
  ),
  'plant_palm': RoomItemStyle(
    slot: RoomSlot.plant,
    title: 'Palm tree',
    emoji: '🌴',
    background: Color(0xFFCFE8C0),
    unlockLevel: 6,
  ),
};

/// What each slot holds until a child chooses something else.
const defaultRoomItems = <RoomSlot, String>{
  RoomSlot.rug: 'rug_sand',
  RoomSlot.wall: 'wall_clock',
  RoomSlot.plant: 'plant_seedling',
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
