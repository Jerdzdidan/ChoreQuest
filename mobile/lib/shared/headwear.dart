import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// Hats and other headwear, keyed as the server stores them.
///
/// "No hat" comes first and is what every child starts with, so a hat can
/// always be taken off. The Adventure Cap is open from the start so there is
/// one to try. Names are the Phase 3 plan's; the emoji are placeholders until
/// the drawn headwear (A0/L1) arrives.
const headwear = <String, CosmeticStyle>{
  'none': CosmeticStyle(
    title: 'No hat',
    emoji: '😀',
    background: Color(0xFFE4E7EA),
  ),
  'adventure_cap': CosmeticStyle(
    title: 'Adventure Cap',
    asset: 'assets/cosmetics/headwear/adventure_cap.png',
    emoji: '👒',
    background: Color(0xFFFFF1C2),
  ),
  'ninja_headband': CosmeticStyle(
    title: 'Ninja Headband',
    asset: 'assets/cosmetics/headwear/ninja_headband.png',
    emoji: '🎀',
    background: Color(0xFFF7DEE9),
    unlockLevel: 2,
  ),
  'pirate_hat': CosmeticStyle(
    title: 'Pirate Hat',
    asset: 'assets/cosmetics/headwear/pirate_hat.png',
    emoji: '⚓',
    background: Color(0xFFD5E6F5),
    unlockLevel: 3,
  ),
  'wizard_hat': CosmeticStyle(
    title: 'Wizard Hat',
    asset: 'assets/cosmetics/headwear/wizard_hat.png',
    emoji: '🎩',
    background: Color(0xFFE4E1FF),
    unlockLevel: 4,
  ),
  'superhero_mask': CosmeticStyle(
    title: 'Superhero Mask',
    asset: 'assets/cosmetics/headwear/superhero_mask.png',
    emoji: '🎭',
    background: Color(0xFFFFE3CC),
    unlockLevel: 5,
  ),
  'space_helmet': CosmeticStyle(
    title: 'Space Helmet',
    asset: 'assets/cosmetics/headwear/space_helmet.png',
    emoji: '🌠',
    background: Color(0xFFD9F0CB),
    unlockLevel: 6,
  ),
};

/// What every child wears on their head until they choose something else.
const defaultHeadwear = 'none';

/// The headwear for [key], or the default for a key this version does not
/// know.
CosmeticStyle headwearFor(String key) =>
    headwear[key] ?? headwear[defaultHeadwear]!;
