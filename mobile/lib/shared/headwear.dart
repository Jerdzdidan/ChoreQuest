import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// Hats and other headwear, keyed as the server stores them.
///
/// "No hat" comes first and is what every child starts with, so a hat can
/// always be taken off again. Titles, levels and placeholder art are a
/// starting set for the art team to replace (A0).
const headwear = <String, CosmeticStyle>{
  'none': CosmeticStyle(
    title: 'No hat',
    emoji: '😀',
    background: Color(0xFFE4E7EA),
  ),
  'sun_hat': CosmeticStyle(
    title: 'Sun hat',
    emoji: '👒',
    background: Color(0xFFFFF1C2),
  ),
  'party_hat': CosmeticStyle(
    title: 'Party hat',
    emoji: '🎉',
    background: Color(0xFFF7DEE9),
    unlockLevel: 2,
  ),
  'top_hat': CosmeticStyle(
    title: 'Top hat',
    emoji: '🎩',
    background: Color(0xFFE4E1FF),
    unlockLevel: 3,
  ),
  'crown': CosmeticStyle(
    title: 'Crown',
    emoji: '👑',
    background: Color(0xFFFFE7B8),
    unlockLevel: 4,
  ),
  'rescue_helmet': CosmeticStyle(
    title: 'Rescue helmet',
    emoji: '⛑',
    background: Color(0xFFFFE3CC),
    unlockLevel: 5,
  ),
  'graduation_cap': CosmeticStyle(
    title: 'Clever cap',
    emoji: '🎓',
    background: Color(0xFFD5E6F5),
    unlockLevel: 6,
  ),
};

/// What every child wears on their head until they choose something else.
const defaultHeadwear = 'none';

/// The headwear for [key], or the default for a key this version does not
/// know.
CosmeticStyle headwearFor(String key) =>
    headwear[key] ?? headwear[defaultHeadwear]!;
