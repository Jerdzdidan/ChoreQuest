import 'package:flutter/material.dart';

/// The phone's back camera, on a strap, is the only view (Phase 5 decision 1):
/// on the head or the chest, the camera sees the child's hands. Holding the
/// phone is not offered.

/// For the parent, when assigning a quest the model checks.
const strapAssignWarning =
    "This quest needs the phone on a head or chest strap so the camera sees your child's hands. "
    'Use a strap made for phones. Never hang a phone around a child\'s neck on a cord.';

/// Wherever a strap is shown.
const neckCordWarning = "Never hang a phone around a child's neck on a cord.";

/// Which strap a picture shows.
enum StrapKind {
  head('Head strap'),
  chest('Chest strap');

  const StrapKind(this.label);

  final String label;
}

/// A simple drawing of a phone worn on a strap, camera facing out.
class StrapPicture extends StatelessWidget {
  const StrapPicture(this.kind, {super.key, this.size = 96});

  final StrapKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'A phone on a ${kind.label.toLowerCase()}',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _StrapPainter(
            kind,
            body: scheme.onSurfaceVariant,
            strap: scheme.tertiary,
            phone: scheme.primary,
            lens: scheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _StrapPainter extends CustomPainter {
  _StrapPainter(this.kind, {required this.body, required this.strap, required this.phone, required this.lens});

  final StrapKind kind;
  final Color body;
  final Color strap;
  final Color phone;
  final Color lens;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final line = Paint()
      ..color = body
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round;
    final band = Paint()
      ..color = strap
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * s
      ..strokeCap = StrokeCap.round;

    void phoneAt(Offset centre, double width, double height) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: width * s, height: height * s),
        Radius.circular(3 * s),
      );
      canvas.drawRRect(rect, Paint()..color = phone);
      canvas.drawCircle(centre, 3.2 * s, Paint()..color = lens);
    }

    switch (kind) {
      case StrapKind.head:
        // Shoulders, head, and the band round the forehead.
        canvas.drawArc(Rect.fromLTWH(14 * s, 78 * s, 72 * s, 44 * s), 3.3, 2.82, false, line);
        canvas.drawOval(Rect.fromLTWH(28 * s, 16 * s, 44 * s, 56 * s), line);
        canvas.drawArc(Rect.fromLTWH(26 * s, 26 * s, 48 * s, 18 * s), 0.05, 3.04, false, band);
        phoneAt(Offset(50 * s, 32 * s), 22, 14);
      case StrapKind.chest:
        // Head, shoulders and body, and a harness over both shoulders.
        canvas.drawCircle(Offset(50 * s, 18 * s), 11 * s, line);
        final torso = Path()
          ..moveTo(22 * s, 98 * s)
          ..lineTo(24 * s, 46 * s)
          ..quadraticBezierTo(26 * s, 34 * s, 40 * s, 33 * s)
          ..lineTo(60 * s, 33 * s)
          ..quadraticBezierTo(74 * s, 34 * s, 76 * s, 46 * s)
          ..lineTo(78 * s, 98 * s);
        canvas.drawPath(torso, line);
        canvas.drawLine(Offset(36 * s, 36 * s), Offset(50 * s, 60 * s), band);
        canvas.drawLine(Offset(64 * s, 36 * s), Offset(50 * s, 60 * s), band);
        canvas.drawLine(Offset(26 * s, 66 * s), Offset(74 * s, 66 * s), band);
        phoneAt(Offset(50 * s, 62 * s), 16, 24);
    }
  }

  @override
  bool shouldRepaint(_StrapPainter old) =>
      old.kind != kind || old.body != body || old.strap != strap || old.phone != phone || old.lens != lens;
}

/// Both straps side by side, each named.
class StrapPictures extends StatelessWidget {
  const StrapPictures({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 24,
      runSpacing: 8,
      children: [
        for (final kind in StrapKind.values)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StrapPicture(kind, size: size),
              const SizedBox(height: 4),
              Text(kind.label, style: text.labelLarge),
            ],
          ),
      ],
    );
  }
}

/// A warning about straps, with the pictures when there is room for them.
class StrapNotice extends StatelessWidget {
  const StrapNotice({super.key, required this.text, this.pictures = false});

  final String text;
  final bool pictures;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: scheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: style.bodyMedium?.copyWith(color: scheme.onSecondaryContainer)),
              ),
            ],
          ),
          if (pictures) ...[
            const SizedBox(height: 12),
            const StrapPictures(size: 80),
          ],
        ],
      ),
    );
  }
}
