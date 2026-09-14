import 'package:flutter/material.dart';

/// A labelled figure on a tinted tile.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final figure = Text(
      value,
      style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final symbol = icon;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          if (symbol == null)
            figure
          else
            Row(
              children: [
                Icon(symbol, size: 24, color: iconColor),
                const SizedBox(width: 6),
                Flexible(child: figure),
              ],
            ),
        ],
      ),
    );
  }
}

/// Two tiles side by side, kept the same height when one label wraps and the
/// other does not.
class StatTilePair extends StatelessWidget {
  const StatTilePair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Expanded(child: right),
        ],
      ),
    );
  }
}
