import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/cosmetics.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/character_portrait.dart';
import '../../shared/cosmetic_style.dart';
import '../../shared/cosmetics.dart';
import '../../shared/headwear.dart';
import '../../shared/inline_error.dart';
import '../../shared/leveling.dart';
import '../../shared/pets.dart';
import 'badges_screen.dart';
import 'category_row.dart';
import 'child_providers.dart';
import 'choose_avatar_screen.dart';
import 'room_decor_screen.dart';
import 'wardrobe.dart';

/// My Avatar: the child's character, dressed in what they have chosen, and
/// rows of outfits, hats and pets to choose from. Items a child's level has
/// not reached yet are shown with a lock and the level they need, so there is
/// always something to look forward to.
///
/// Badges and the room are one tap away at the top.
class AvatarScreen extends ConsumerStatefulWidget {
  const AvatarScreen({super.key, this.showAppBar = true});

  /// False when the screen is a tab with the shell's own bar.
  final bool showAppBar;

  @override
  ConsumerState<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends ConsumerState<AvatarScreen> {
  String? _busy;
  String? _error;

  Future<void> _wear(CosmeticCategory category, String key) async {
    setState(() {
      _busy = '${category.name}:$key';
      _error = null;
    });
    try {
      await ref.read(wardrobeProvider.notifier).equip(category, key);
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
    final me = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ChildSession s) => s,
      _ => null,
    };
    if (me == null) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final progress = ref.watch(progressProvider);
    final level = progress.hasValue ? levelFor(progress.requireValue.xp).level : 1;
    final wardrobe = ref.watch(wardrobeProvider);
    final worn = wardrobe.value;
    final error = _error;

    CosmeticStyle wearing(CosmeticCategory category) =>
        cosmeticsIn(category)[worn == null ? defaultKeyFor(category) : wornIn(worn, category)] ??
        cosmeticsIn(category).values.first;

    final hatKey = worn == null ? defaultHeadwear : wornIn(worn, CosmeticCategory.headwear);
    final petKey = worn == null ? defaultPet : wornIn(worn, CosmeticCategory.pet);

    final body = RefreshIndicator(
      onRefresh: () => ref.refresh(wardrobeProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        child: CharacterPortrait(
                          avatar: me.avatar,
                          outfit: wearing(CosmeticCategory.outfit),
                          headwear: hatKey == defaultHeadwear ? null : headwearFor(hatKey),
                          pet: petKey == defaultPet ? null : petFor(petKey),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QuickButton(
                        icon: Icons.military_tech_rounded,
                        label: 'Badges',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const BadgesScreen()),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _QuickButton(
                        icon: Icons.chair_rounded,
                        label: 'Room',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RoomDecorScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // A wrap, not a row: with large text on a narrow phone the button
          // moves under the level instead of squeezing it to a sliver.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'You are level $level',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChooseAvatarScreen()),
                ),
                icon: const Icon(Icons.pets_rounded),
                label: const Text('Change animal'),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            InlineError(error),
          ],
          if (wardrobe.hasError && worn == null) ...[
            const SizedBox(height: 8),
            const InlineError("Couldn't load your things. Pull down to try again."),
          ],
          for (final (category, title) in const [
            (CosmeticCategory.outfit, 'Outfits'),
            (CosmeticCategory.headwear, 'Hats'),
            (CosmeticCategory.pet, 'Pets'),
          ]) ...[
            const SizedBox(height: 16),
            Text(title, style: text.titleMedium),
            const SizedBox(height: 6),
            CategoryRow(
              category: category,
              level: level,
              wardrobe: worn,
              busy: _busy,
              onWear: (key) => _wear(category, key),
            ),
          ],
        ],
      ),
    );

    if (!widget.showAppBar) return body;
    return Scaffold(appBar: AppBar(title: const Text('My Avatar')), body: body);
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 76,
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: scheme.onPrimaryContainer, size: 28),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
