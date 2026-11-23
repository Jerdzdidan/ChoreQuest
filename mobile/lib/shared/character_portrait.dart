import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'avatars.dart';
import 'cosmetic_style.dart';

/// The child's character: a body dressed in what they are wearing, with their
/// pet beside them.
///
/// A paper doll (AV-4). Every layer is a picture the size of the whole
/// character with the item already in place (tools/export_layers.py), so the
/// body, the outfit and the headwear are stacked at one size and one
/// alignment, and there is no offset anywhere to get wrong. Taking a hat off
/// leaves the body's own head. The pet is not worn: it stands beside the body
/// on the same ground line.
///
/// An item with no layer yet is drawn as a sticker over the body instead, the
/// way every item was before, so registries can move across one at a time.
class CharacterPortrait extends StatelessWidget {
  const CharacterPortrait({
    super.key,
    required this.avatar,
    required this.body,
    required this.outfit,
    required this.headwear,
    required this.pet,
    this.size = 180,
    this.showGuide = false,
  });

  /// The animal the child signs in with. The character is a separate figure;
  /// the animal's colour is the soft tint behind it.
  final String avatar;
  final CosmeticStyle body;
  final CosmeticStyle outfit;

  /// Null when the child has no hat on.
  final CosmeticStyle? headwear;

  /// Null when the child has no pet with them.
  final CosmeticStyle? pet;
  final double size;

  /// Draws the guide boxes over the character (AV-5). Debug builds only: in a
  /// release build it is ignored and the overlay is not compiled in.
  final bool showGuide;

  @override
  Widget build(BuildContext context) {
    final headwear = this.headwear;
    final pet = this.pet;

    // The character's square: its feet are on the square's bottom edge, which
    // is the ground line the pet stands on too.
    final doll = size * 0.92;
    final ground = size * 0.04;
    final left = size * 0.04;

    return Semantics(
      label: [
        'Your character, with ${body.title.toLowerCase()},',
        'wearing the ${outfit.title}',
        if (headwear != null) 'and the ${headwear.title}',
        if (pet != null) 'with ${pet.title}',
      ].join(' '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: size * 1.35,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: left + doll * 0.09,
                top: size - ground - doll * 0.91,
                child: Container(
                  width: doll * 0.82,
                  height: doll * 0.82,
                  decoration: BoxDecoration(
                    color: avatarFor(avatar).background,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                left: left,
                bottom: ground,
                width: doll,
                height: doll,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _Worn(style: body, side: doll, sticker: _Sticker.body),
                    _Worn(style: outfit, side: doll, sticker: _Sticker.torso),
                    if (headwear != null) _Worn(style: headwear, side: doll, sticker: _Sticker.head),
                    if (kDebugMode && showGuide)
                      Positioned.fill(child: CustomPaint(painter: _GuidePainter())),
                  ],
                ),
              ),
              if (pet != null)
                Positioned(
                  right: 0,
                  bottom: ground,
                  child: _sticker(pet, size * 0.36),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where an item without a layer is stuck on, as before the paper doll.
enum _Sticker { body, torso, head }

/// One worn item: its layer across the whole square, or its sticker.
class _Worn extends StatelessWidget {
  const _Worn({required this.style, required this.side, required this.sticker});

  final CosmeticStyle style;
  final double side;
  final _Sticker sticker;

  @override
  Widget build(BuildContext context) {
    final layer = style.layer;
    if (layer != null) {
      return Positioned.fill(
        child: Image.asset(
          layer,
          width: side,
          height: side,
          fit: BoxFit.fill,
          // Pixel art: crisp edges rather than a blur when it grows.
          filterQuality: FilterQuality.none,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }

    return switch (sticker) {
      _Sticker.body => Positioned.fill(child: Center(child: _sticker(style, side * 0.7))),
      _Sticker.torso => Positioned(
          bottom: side * 0.04,
          left: side * 0.33,
          child: _sticker(style, side * 0.34),
        ),
      _Sticker.head => Positioned(
          top: -side * 0.02,
          left: side * 0.35,
          child: _sticker(style, side * 0.3),
        ),
    };
  }
}

/// An item drawn on its own: its picture when there is one, otherwise its
/// placeholder emoji on a circle.
Widget _sticker(CosmeticStyle style, double size) {
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

/// The boxes tools/export_layers.py checks every layer against, on the
/// 16 x 16 character cell: headwear above the shoulders, a shirt over the
/// torso and arms, trousers over the legs, and the feet line. Change both
/// together.
const _cell = 16.0;
const _headBox = Rect.fromLTRB(0, 0, 16, 8);
const _torsoBox = Rect.fromLTRB(0, 6, 16, 15);
const _legsBox = Rect.fromLTRB(3, 13, 13, 16);
const _feetLine = 16.0;

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _cell;
    Rect at(Rect box) => Rect.fromLTRB(
          box.left * scale,
          box.top * scale,
          box.right * scale,
          box.bottom * scale,
        );
    Paint line(Color colour) => Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(at(_headBox), line(const Color(0xFFDC2828)));
    canvas.drawRect(at(_torsoBox), line(const Color(0xFF285ADC)));
    canvas.drawRect(at(_legsBox), line(const Color(0xFF28A050)));
    canvas.drawLine(
      Offset(0, _feetLine * scale),
      Offset(size.width, _feetLine * scale),
      line(const Color(0xFF000000)),
    );
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) => false;
}
