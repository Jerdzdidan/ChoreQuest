import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// Pets that keep a child's character company, keyed as the server stores
/// them.
///
/// "No pet" comes first and is what every child starts with; Buddy the Dog is
/// open from the start so there is always one to choose. Names are the Phase 3
/// plan's; the emoji are placeholders until the pet sprites (A1/L1) arrive.
const pets = <String, CosmeticStyle>{
  'none': CosmeticStyle(
    title: 'No pet',
    emoji: '🏠',
    background: Color(0xFFE4E7EA),
  ),
  'dog': CosmeticStyle(
    title: 'Buddy the Dog',
    emoji: '🐶',
    background: Color(0xFFE9DCD2),
  ),
  'cat': CosmeticStyle(
    title: 'Whiskers the Cat',
    emoji: '🐱',
    background: Color(0xFFFFF1C2),
    unlockLevel: 2,
  ),
  'rabbit': CosmeticStyle(
    title: 'Hopper the Rabbit',
    emoji: '🐰',
    background: Color(0xFFF7DDE8),
    unlockLevel: 3,
  ),
  'turtle': CosmeticStyle(
    title: 'Shelly the Turtle',
    emoji: '🐢',
    background: Color(0xFFD7F0C9),
    unlockLevel: 4,
  ),
  'parrot': CosmeticStyle(
    title: 'Chirpy the Parrot',
    emoji: '🐦',
    background: Color(0xFFD5E6F5),
    unlockLevel: 5,
  ),
  'dragon': CosmeticStyle(
    title: 'Sparkle the Dragon',
    emoji: '🐉',
    background: Color(0xFFE4E1FF),
    unlockLevel: 6,
  ),
};

/// Every child starts without a pet.
const defaultPet = 'none';

/// The pet for [key], or the default for a key this version does not know.
CosmeticStyle petFor(String key) => pets[key] ?? pets[defaultPet]!;
