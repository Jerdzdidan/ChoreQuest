import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/cosmetics.dart';
import '../../shared/cosmetics.dart';
import '../../shared/leveling.dart';
import 'child_providers.dart';
import 'cosmetic_unlocks.dart';

/// The child's cosmetics as the server records them, brought up to date with
/// their level first: whatever the level unlocks is recorded (U6) before the
/// list is read, so a child who has just levelled up can wear the new items
/// straight away.
final wardrobeProvider = AsyncNotifierProvider.autoDispose<WardrobeController, Wardrobe>(
  WardrobeController.new,
);

class WardrobeController extends AsyncNotifier<Wardrobe> {
  @override
  Future<Wardrobe> build() async {
    final api = ref.watch(childApiProvider);
    final progress = await ref.watch(progressProvider.future);
    await CosmeticUnlocks(api).sync(levelFor(progress.xp).level);
    return api.cosmetics();
  }

  /// Puts on an item the child owns. The server keeps one per category and
  /// answers with the whole wardrobe, which replaces what is shown.
  Future<void> equip(CosmeticCategory category, String key) async {
    final wardrobe = await ref.read(childApiProvider).equip(category, key);
    state = AsyncData(wardrobe);
  }
}

/// What a category shows as worn: the item on, or the registry's default when
/// the child has not chosen one.
String wornIn(Wardrobe wardrobe, CosmeticCategory category) =>
    wardrobe.equippedIn(category) ?? defaultKeyFor(category);

String defaultKeyFor(CosmeticCategory category) => cosmeticsIn(category).keys.first;
