import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/cosmetics.dart';
import '../../shared/cosmetic_style.dart';
import '../../shared/cosmetics.dart';
import '../../shared/inline_error.dart';
import '../../shared/leveling.dart';
import '../../shared/theme.dart';
import 'category_row.dart';
import 'child_providers.dart';
import 'wardrobe.dart';

/// The child's room: one scene with three places to decorate, the rug, the
/// wall and a plant, each swapped from what the child has unlocked.
///
/// The fixed-slot room the plan settled on, not a tile map. What is chosen is
/// saved on the server (U7), so the room looks the same next time.
class RoomDecorScreen extends ConsumerStatefulWidget {
  const RoomDecorScreen({super.key});

  @override
  ConsumerState<RoomDecorScreen> createState() => _RoomDecorScreenState();
}

class _RoomDecorScreenState extends ConsumerState<RoomDecorScreen> {
  String? _busy;
  String? _error;

  Future<void> _place(CosmeticCategory slot, String key) async {
    setState(() {
      _busy = '${slot.name}:$key';
      _error = null;
    });
    try {
      await ref.read(wardrobeProvider.notifier).equip(slot, key);
    } on ApiRejected catch (e) {
      if (mounted) setState(() => _error = e.errorFor('key') ?? e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final progress = ref.watch(progressProvider);
    final level = progress.hasValue ? levelFor(progress.requireValue.xp).level : 1;
    final loaded = ref.watch(wardrobeProvider);
    final wardrobe = loaded.value;
    final error = _error;

    CosmeticStyle inSlot(CosmeticCategory slot) {
      final key = wardrobe == null ? defaultKeyFor(slot) : wornIn(wardrobe, slot);
      return cosmeticsIn(slot)[key] ?? cosmeticsIn(slot).values.first;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My room')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(wardrobeProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            RoomScene(
              rug: inSlot(CosmeticCategory.rug),
              wall: inSlot(CosmeticCategory.wall),
              plant: inSlot(CosmeticCategory.plant),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              InlineError(error),
            ],
            if (loaded.hasError && wardrobe == null) ...[
              const SizedBox(height: 12),
              const InlineError("Couldn't load your things. Pull down to try again."),
            ],
            for (final (slot, title) in const [
              (CosmeticCategory.rug, 'Rugs'),
              (CosmeticCategory.wall, 'Wall art'),
              (CosmeticCategory.plant, 'Plants'),
            ]) ...[
              const SizedBox(height: 16),
              Text(title, style: text.titleMedium),
              const SizedBox(height: 6),
              CategoryRow(
                category: slot,
                level: level,
                wardrobe: wardrobe,
                busy: _busy,
                onWear: (key) => _place(slot, key),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The room itself: a wall with a picture, a floor with a rug and a plant in
/// the corner. Each is its placeholder until the room art (A2) arrives.
class RoomScene extends StatelessWidget {
  const RoomScene({super.key, required this.rug, required this.wall, required this.plant});

  final CosmeticStyle rug;
  final CosmeticStyle wall;
  final CosmeticStyle plant;

  @override
  Widget build(BuildContext context) {
    final room = QuestColors.of(context).room;

    return Semantics(
      label: 'Your room: the ${wall.title} on the wall, the ${rug.title} on the floor '
          'and the ${plant.title} in the corner',
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final h = box.maxHeight;
                return Stack(
                  children: [
                    // Wall and floor.
                    Positioned.fill(child: Container(color: room.wall)),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: h * 0.42,
                      child: Container(color: room.floor),
                    ),
                    // The picture on the wall, framed.
                    Positioned(
                      top: h * 0.1,
                      left: w * 0.34,
                      width: w * 0.32,
                      height: h * 0.34,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: room.frame, width: 4),
                        ),
                        child: CosmeticArt(wall, size: h * 0.22),
                      ),
                    ),
                    // The rug on the floor, seen from the side as an oval.
                    Positioned(
                      bottom: h * 0.08,
                      left: w * 0.2,
                      width: w * 0.5,
                      height: h * 0.2,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: rug.background,
                          borderRadius: BorderRadius.all(Radius.elliptical(w * 0.25, h * 0.1)),
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: Text(rug.emoji ?? '', style: TextStyle(fontSize: h * 0.08)),
                      ),
                    ),
                    // The plant in the corner.
                    Positioned(
                      right: w * 0.05,
                      bottom: h * 0.2,
                      child: CosmeticArt(plant, size: h * 0.26),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
