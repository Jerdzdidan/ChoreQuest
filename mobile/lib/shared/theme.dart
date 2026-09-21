import 'package:flutter/material.dart';

import '../core/models/chore.dart';

/// Pine green: the colour of "earned" throughout the project's plans and
/// figures, so the app and the manuscript read as one system.
const brandSeed = Color(0xFF1C6449);

/// A pale, pine-tinted ground for every screen, so nothing sits on flat white
/// while cards stay white and stand out from it.
const _ground = Color(0xFFF1F6F3);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: brandSeed).copyWith(
    surface: _ground,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: _ground,
    extensions: const [QuestColors.standard],
    appBarTheme: const AppBarTheme(backgroundColor: _ground),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      shadowColor: brandSeed.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: scheme.primaryContainer,
      elevation: 3,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // A finite minimum. Buttons in lists and stretched columns still run
        // full width because their parent sizes them; an infinite minimum here
        // made any filled button inside a row or a dialog's action bar throw.
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// A pale fill and a deep ink that read well on it.
typedef Tint = ({Color fill, Color ink});

/// The game's colours, beside Material's scheme: XP gold, one colour per place
/// in the home, the gradient behind header bands, and the colours the map and
/// the room are drawn in until their art arrives. Every child and parent
/// screen reads them from here (`QuestColors.of(context)`), so changing a
/// colour is a change to this one file.
@immutable
class QuestColors extends ThemeExtension<QuestColors> {
  const QuestColors({
    required this.xp,
    required this.xpStar,
    required this.flame,
    required this.header,
    required this.places,
    required this.done,
    required this.waiting,
    required this.saved,
    required this.screenTime,
    required this.confetti,
    required this.map,
    required this.room,
    required this.review,
    required this.approved,
  });

  /// Anything to do with XP and levels.
  final Tint xp;

  /// The star beside an XP figure.
  final Color xpStar;

  /// Streaks.
  final Color flame;

  /// Header bands, top to bottom.
  final List<Color> header;

  /// Kitchen, bedroom, study table, outdoor area and everything else.
  final Map<QuestLocation, Tint> places;

  /// A quest done and approved.
  final Color done;

  /// A photo waiting for a grown-up.
  final Color waiting;

  /// A photo kept on the phone to send later, and anything calm and
  /// informational.
  final Tint saved;

  /// Screen time: minutes earned and the wallet.
  final Tint screenTime;

  /// The celebration when a photo is approved.
  final List<Color> confetti;

  /// The quest map as drawn until its art (A3) arrives: the ground, and the
  /// trail from place to place.
  final ({Color ground, Color trail}) map;

  /// The child's room as drawn until its art (A2) arrives.
  final ({Color wall, Color floor, Color frame}) room;

  /// A photo the checker left to a grown-up: orange, and always with a flag,
  /// so it never depends on colour alone.
  final Tint review;

  /// A photo the checker approved on its own: green, with a tick.
  final Tint approved;

  static const standard = QuestColors(
    xp: (fill: Color(0xFFFFF1C2), ink: Color(0xFF6E5200)),
    xpStar: Color(0xFFE0A100),
    flame: Color(0xFFD9480F),
    header: [Color(0xFF1C6449), Color(0xFF2E8B6B)],
    places: {
      QuestLocation.kitchen: (fill: Color(0xFFFFE3CC), ink: Color(0xFF833F12)),
      QuestLocation.bedroom: (fill: Color(0xFFE4E1FF), ink: Color(0xFF3B3585)),
      QuestLocation.study: (fill: Color(0xFFD5F0EC), ink: Color(0xFF0F5E56)),
      QuestLocation.outdoor: (fill: Color(0xFFD9F0CB), ink: Color(0xFF2B6320)),
      QuestLocation.other: (fill: Color(0xFFE4E7EA), ink: Color(0xFF3F4A45)),
    },
    done: Color(0xFF2E7D32),
    waiting: Color(0xFF9A6412),
    saved: (fill: Color(0xFFDCE6F2), ink: Color(0xFF1D4A73)),
    screenTime: (fill: Color(0xFFDCE6F2), ink: Color(0xFF1D4A73)),
    confetti: [
      Color(0xFF2E7D32),
      Color(0xFFFFC107),
      Color(0xFF1E88E5),
      Color(0xFFE91E63),
      Color(0xFFFF7043),
      Color(0xFF8E24AA),
    ],
    map: (ground: Color(0xFFE3F1DA), trail: Color(0xFFE6CF9F)),
    room: (wall: Color(0xFFF3E7D3), floor: Color(0xFFD9B98C), frame: Color(0xFF8A6A45)),
    review: (fill: Color(0xFFFFE2CC), ink: Color(0xFF9C3D00)),
    approved: (fill: Color(0xFFD5EFD8), ink: Color(0xFF1E5E2A)),
  );

  /// The colours for this screen, or the standard set outside a themed app.
  static QuestColors of(BuildContext context) =>
      Theme.of(context).extension<QuestColors>() ?? standard;

  Tint place(QuestLocation location) =>
      places[location] ?? places[QuestLocation.other]!;

  @override
  QuestColors copyWith({
    Tint? xp,
    Color? xpStar,
    Color? flame,
    List<Color>? header,
    Map<QuestLocation, Tint>? places,
    Color? done,
    Color? waiting,
    Tint? saved,
    Tint? screenTime,
    List<Color>? confetti,
    ({Color ground, Color trail})? map,
    ({Color wall, Color floor, Color frame})? room,
    Tint? review,
    Tint? approved,
  }) =>
      QuestColors(
        xp: xp ?? this.xp,
        xpStar: xpStar ?? this.xpStar,
        flame: flame ?? this.flame,
        header: header ?? this.header,
        places: places ?? this.places,
        done: done ?? this.done,
        waiting: waiting ?? this.waiting,
        saved: saved ?? this.saved,
        screenTime: screenTime ?? this.screenTime,
        confetti: confetti ?? this.confetti,
        map: map ?? this.map,
        room: room ?? this.room,
        review: review ?? this.review,
        approved: approved ?? this.approved,
      );

  @override
  QuestColors lerp(QuestColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// A band of the header gradient behind a screen's top section.
class HeaderBand extends StatelessWidget {
  const HeaderBand({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = QuestColors.of(context).header;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: child,
      ),
    );
  }
}
