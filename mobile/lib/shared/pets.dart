import 'package:flutter/material.dart';

import 'cosmetic_style.dart';

/// Pets that keep a child's character company, keyed as the server stores
/// them.
///
/// "No pet" comes first and is what every child starts with; Buddy the Dog is
/// open from the start so there is always one to choose. The animals are the
/// ones Kenney's Animal Pack Redux draws (L1): the plan's cat, turtle and
/// dragon are not in it, so a panda, a penguin and a monkey take their places
/// rather than leaving three pets without a picture.
const pets = <String, CosmeticStyle>{
  'none': CosmeticStyle(
    title: 'No pet',
    emoji: '🏠',
    background: Color(0xFFE4E7EA),
  ),
  'dog': CosmeticStyle(
    title: 'Buddy the Dog',
    asset: 'assets/cosmetics/pets/dog.png',
    emoji: '🐶',
    background: Color(0xFFE9DCD2),
  ),
  'panda': CosmeticStyle(
    title: 'Bamboo the Panda',
    asset: 'assets/cosmetics/pets/panda.png',
    emoji: '🐼',
    background: Color(0xFFFFF1C2),
    unlockLevel: 2,
  ),
  'rabbit': CosmeticStyle(
    title: 'Hopper the Rabbit',
    asset: 'assets/cosmetics/pets/rabbit.png',
    emoji: '🐰',
    background: Color(0xFFF7DDE8),
    unlockLevel: 3,
  ),
  'penguin': CosmeticStyle(
    title: 'Waddles the Penguin',
    asset: 'assets/cosmetics/pets/penguin.png',
    emoji: '🐧',
    background: Color(0xFFD7F0C9),
    unlockLevel: 4,
  ),
  'parrot': CosmeticStyle(
    title: 'Chirpy the Parrot',
    asset: 'assets/cosmetics/pets/parrot.png',
    emoji: '🐦',
    background: Color(0xFFD5E6F5),
    unlockLevel: 5,
  ),
  'monkey': CosmeticStyle(
    title: 'Mango the Monkey',
    asset: 'assets/cosmetics/pets/monkey.png',
    emoji: '🐵',
    background: Color(0xFFE4E1FF),
    unlockLevel: 6,
  ),
};

/// Every child starts without a pet.
const defaultPet = 'none';

/// The pet for [key], or the default for a key this version does not know.
/// A child who was given the old 'cat', 'turtle' or 'dragon' before L1 falls
/// back to no pet rather than to a missing picture.
CosmeticStyle petFor(String key) => pets[key] ?? pets[defaultPet]!;
