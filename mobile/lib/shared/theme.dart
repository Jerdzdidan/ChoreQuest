import 'package:flutter/material.dart';

/// Pine green: the colour of "earned" throughout the project's plans and
/// figures, so the app and the manuscript read as one system.
const brandSeed = Color(0xFF1C6449);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: brandSeed);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
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
