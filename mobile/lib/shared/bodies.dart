import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// The bodies a child's character can have, each a skin tone with its own
/// hair, keyed as the server stores them.
///
/// Every body is open from the start: who a child is should not be a reward,
/// so bodies stay off the Reward Track and never count as something a level
/// unlocked. The first is what a child with no body recorded shows, so there
/// is nothing to migrate. The animal a child signs in with is separate and
/// unchanged.
const bodies = <String, CosmeticStyle>{
  'body_1': CosmeticStyle(
    title: 'Short brown hair',
    asset: 'assets/cosmetics/icons/body_1.png',
    layer: 'assets/cosmetics/layers/body_1.png',
    emoji: '😊',
    background: Color(0xFFFFE3CC),
  ),
  'body_2': CosmeticStyle(
    title: 'Long black hair',
    asset: 'assets/cosmetics/icons/body_2.png',
    layer: 'assets/cosmetics/layers/body_2.png',
    emoji: '😊',
    background: Color(0xFFF7DEE9),
  ),
  'body_3': CosmeticStyle(
    title: 'Short black hair',
    asset: 'assets/cosmetics/icons/body_3.png',
    layer: 'assets/cosmetics/layers/body_3.png',
    emoji: '😊',
    background: Color(0xFFD5E6F5),
  ),
  'body_4': CosmeticStyle(
    title: 'Black braids',
    asset: 'assets/cosmetics/icons/body_4.png',
    layer: 'assets/cosmetics/layers/body_4.png',
    emoji: '😊',
    background: Color(0xFFD9F0CB),
  ),
};

/// The body every child has until they choose another.
const defaultBody = 'body_1';

/// The body for [key], or the default for a key this version does not know.
CosmeticStyle bodyFor(String key) => bodies[key] ?? bodies[defaultBody]!;
