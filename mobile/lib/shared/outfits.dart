import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// Outfits a child's character can wear, keyed as the server stores them.
///
/// The first is the default every child starts in. Names are the Phase 3
/// plan's. Each outfit is a shirt with its trousers, drawn on the whole
/// character (layer) and cut to its own pixels for the tiles (asset); the
/// emoji stay as the fallback if a picture is ever missing.
const outfits = <String, CosmeticStyle>{
  'rainbow_hoodie': CosmeticStyle(
    title: 'Rainbow Hoodie',
    asset: 'assets/cosmetics/icons/outfit_rainbow_hoodie.png',
    layer: 'assets/cosmetics/layers/outfit_rainbow_hoodie.png',
    emoji: '🌈',
    background: Color(0xFFF7DEE9),
  ),
  'explorer_jacket': CosmeticStyle(
    title: 'Explorer Jacket',
    asset: 'assets/cosmetics/icons/outfit_explorer_jacket.png',
    layer: 'assets/cosmetics/layers/outfit_explorer_jacket.png',
    emoji: '🎒',
    background: Color(0xFFFFE3CC),
    unlockLevel: 2,
  ),
  'ninja_outfit': CosmeticStyle(
    title: 'Ninja Outfit',
    asset: 'assets/cosmetics/icons/outfit_ninja_outfit.png',
    layer: 'assets/cosmetics/layers/outfit_ninja_outfit.png',
    emoji: '🌙',
    background: Color(0xFFE4E7EA),
    unlockLevel: 3,
  ),
  'pirate_coat': CosmeticStyle(
    title: 'Pirate Captain Coat',
    asset: 'assets/cosmetics/icons/outfit_pirate_coat.png',
    layer: 'assets/cosmetics/layers/outfit_pirate_coat.png',
    emoji: '⚓',
    background: Color(0xFFD5E6F5),
    unlockLevel: 4,
  ),
  'superhero_suit': CosmeticStyle(
    title: 'Superhero Suit',
    asset: 'assets/cosmetics/icons/outfit_superhero_suit.png',
    layer: 'assets/cosmetics/layers/outfit_superhero_suit.png',
    emoji: '⚡',
    background: Color(0xFFFFF1C2),
    unlockLevel: 5,
  ),
  'space_suit': CosmeticStyle(
    title: 'Space Voyager Suit',
    asset: 'assets/cosmetics/icons/outfit_space_suit.png',
    layer: 'assets/cosmetics/layers/outfit_space_suit.png',
    emoji: '🚀',
    background: Color(0xFFE4E1FF),
    unlockLevel: 6,
  ),
};

/// What every child wears until they choose something else.
const defaultOutfit = 'rainbow_hoodie';

/// The outfit for [key], or the default for a key this version does not know.
CosmeticStyle outfitFor(String key) => outfits[key] ?? outfits[defaultOutfit]!;
