import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// Pets that keep a child's character company, keyed as the server stores
/// them.
///
/// "No pet" comes first and is what every child starts with; the dog is open
/// from the start so there is always one to choose. Titles, levels and
/// placeholder art are a starting set for the art team to replace (A1).
const pets = <String, CosmeticStyle>{
  'none': CosmeticStyle(
    title: 'No pet',
    emoji: '🏠',
    background: Color(0xFFE4E7EA),
  ),
  'dog': CosmeticStyle(
    title: 'Dog',
    emoji: '🐶',
    background: Color(0xFFE9DCD2),
  ),
  'cat': CosmeticStyle(
    title: 'Cat',
    emoji: '🐱',
    background: Color(0xFFFFF1C2),
    unlockLevel: 2,
  ),
  'rabbit': CosmeticStyle(
    title: 'Rabbit',
    emoji: '🐰',
    background: Color(0xFFF7DDE8),
    unlockLevel: 3,
  ),
  'turtle': CosmeticStyle(
    title: 'Turtle',
    emoji: '🐢',
    background: Color(0xFFD7F0C9),
    unlockLevel: 4,
  ),
  'bird': CosmeticStyle(
    title: 'Bird',
    emoji: '🐦',
    background: Color(0xFFD5E6F5),
    unlockLevel: 5,
  ),
  'hamster': CosmeticStyle(
    title: 'Hamster',
    emoji: '🐹',
    background: Color(0xFFFFE3CC),
    unlockLevel: 6,
  ),
};

/// Every child starts without a pet.
const defaultPet = 'none';

/// The pet for [key], or the default for a key this version does not know.
CosmeticStyle petFor(String key) => pets[key] ?? pets[defaultPet]!;
