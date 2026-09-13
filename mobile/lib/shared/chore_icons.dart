import 'package:flutter/material.dart';

/// How a chore looks: an icon on a colour that marks its kind of work.
///
/// Material icons rather than emoji, deliberately. The icons ship inside the
/// app, so they draw the same on every phone. Newer emoji such as a broom or a
/// laundry basket are missing from the system fonts of the Android 7 and 8
/// handsets this study includes and would render as empty boxes, and for a
/// child who cannot read the label beside the picture, an empty box is the
/// whole chore gone.
const _icons = <String, IconData>{
  'toys': Icons.toys,
  'basket': Icons.local_laundry_service,
  'slippers': Icons.door_front_door,
  'books': Icons.menu_book,
  'bin': Icons.delete_outline,
  'pillow': Icons.king_bed,
  'pet': Icons.pets,
  'bed': Icons.bed,
  'plate': Icons.restaurant,
  'table': Icons.table_restaurant,
  'broom': Icons.cleaning_services,
  'plant': Icons.local_florist,
  'fold': Icons.dry_cleaning,
  'cloth': Icons.window,
  'groceries': Icons.shopping_bag,
  'dishes': Icons.flatware,
  'mop': Icons.water,
  'trash': Icons.recycling,
  'laundry': Icons.checkroom,
  'wardrobe': Icons.door_sliding,
  'rice': Icons.rice_bowl,
  'sink': Icons.wash,
  'shoes': Icons.hiking,
  'snack': Icons.bakery_dining,
};

/// Background and foreground per category, as a pale fill with a deep ink so
/// the icon holds its contrast.
const _categoryColours = <String, (Color, Color)>{
  'tidying': (Color(0xFFFFF1C2), Color(0xFF6E5200)),
  'bedroom': (Color(0xFFE4E1FF), Color(0xFF3B3585)),
  'care': (Color(0xFFD9F0CB), Color(0xFF2B6320)),
  'kitchen': (Color(0xFFFFE3CC), Color(0xFF833F12)),
  'cleaning': (Color(0xFFD6E7F5), Color(0xFF1D4A73)),
  'laundry': (Color(0xFFF7DEE9), Color(0xFF822B52)),
};

class ChoreIcon extends StatelessWidget {
  const ChoreIcon({
    super.key,
    required this.icon,
    required this.category,
    this.size = 56,
  });

  final String icon;
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) =
        _categoryColours[category] ?? (const Color(0xFFE2EFE7), const Color(0xFF12503A));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(
        _icons[icon] ?? Icons.star_rounded,
        size: size * 0.55,
        color: foreground,
      ),
    );
  }
}
