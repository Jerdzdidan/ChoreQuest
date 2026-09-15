import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// Outfits a child's character can wear, keyed as the server stores them.
///
/// The first is the default every child starts in. Titles, levels and
/// placeholder art are a starting set for the art team to replace (A0).
const outfits = <String, CosmeticStyle>{
  'everyday': CosmeticStyle(
    title: 'Everyday clothes',
    emoji: '👕',
    background: Color(0xFFDCE6F2),
  ),
  'sports_kit': CosmeticStyle(
    title: 'Sports kit',
    emoji: '🎽',
    background: Color(0xFFD9F0CB),
    unlockLevel: 2,
  ),
  'rain_jacket': CosmeticStyle(
    title: 'Rain jacket',
    emoji: '☔',
    background: Color(0xFFFFF1C2),
    unlockLevel: 3,
  ),
  'explorer': CosmeticStyle(
    title: 'Explorer gear',
    emoji: '🎒',
    background: Color(0xFFFFE3CC),
    unlockLevel: 4,
  ),
  'hero_cape': CosmeticStyle(
    title: 'Hero cape',
    emoji: '⚡',
    background: Color(0xFFE4E1FF),
    unlockLevel: 5,
  ),
  'space_suit': CosmeticStyle(
    title: 'Space suit',
    emoji: '🚀',
    background: Color(0xFFD5E6F5),
    unlockLevel: 6,
  ),
};

/// What every child wears until they choose something else.
const defaultOutfit = 'everyday';

/// The outfit for [key], or the default for a key this version does not know.
CosmeticStyle outfitFor(String key) => outfits[key] ?? outfits[defaultOutfit]!;
