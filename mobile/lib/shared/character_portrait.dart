import 'package:flutter/material.dart';

import 'avatars.dart';
import 'cosmetic_style.dart';

/// The child's character: their animal, dressed in what they are wearing, with
/// their pet beside them.
///
/// Drawn in layers, the way the character art (A0) is meant to stack: the base
/// body, then the outfit, then the headwear, with the pet alongside. Until
/// that art arrives each layer is its placeholder emoji; once an item's asset
/// is set, the drawn layer takes its place with nothing else changing.
class CharacterPortrait extends StatelessWidget {
  const CharacterPortrait({
    super.key,
    required this.avatar,
    required this.outfit,
    required this.headwear,
    required this.pet,
    this.size = 180,
  });

  final String avatar;
  final CosmeticStyle outfit;

  /// Null when the child has no hat on.
  final CosmeticStyle? headwear;

  /// Null when the child has no pet with them.
  final CosmeticStyle? pet;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = avatarFor(avatar);
    final headwear = this.headwear;
    final pet = this.pet;

    return Semantics(
      label: [
        'Your character: the ${avatarName(avatar).toLowerCase()}',
        'wearing the ${outfit.title}',
        if (headwear != null) 'and the ${headwear.title}',
        if (pet != null) 'with ${pet.title}',
      ].join(' '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: size * 1.35,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size * 0.82,
                height: size * 0.82,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: base.background, shape: BoxShape.circle),
                child: Text(base.emoji, style: TextStyle(fontSize: size * 0.42)),
              ),
              Positioned(
                bottom: size * 0.02,
                child: _Layer(style: outfit, size: size * 0.3),
              ),
              if (headwear != null)
                Positioned(
                  top: -size * 0.02,
                  child: _Layer(style: headwear, size: size * 0.28),
                ),
              if (pet != null)
                Positioned(
                  right: 0,
                  bottom: size * 0.04,
                  child: _Layer(style: pet, size: size * 0.32),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Layer extends StatelessWidget {
  const _Layer({required this.style, required this.size});

  final CosmeticStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = style.asset;
    if (asset != null) {
      return Image.asset(asset, width: size, height: size, filterQuality: FilterQuality.none);
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Text(style.emoji ?? '', style: TextStyle(fontSize: size * 0.5)),
    );
  }
}
