import 'package:flutter/material.dart';

/// The colors offered when picking a player color — vivid, reasonably
/// distinct, plus white. Stored as ARGB ints so they serialize trivially (and
/// so we never touch the deprecated Color value accessor).
const List<int> kPlayerPalette = <int>[
  0xFFE53935, // red
  0xFFFB8C00, // orange
  0xFFFDD835, // amber
  0xFF43A047, // green
  0xFF00ACC1, // cyan
  0xFF1E88E5, // blue
  0xFF3949AB, // indigo
  0xFF8E24AA, // purple
  0xFFD81B60, // pink
  0xFF00897B, // teal
  0xFF6D4C41, // brown
  0xFF546E7A, // blue grey
  0xFFFFFFFF, // white
];

/// A readable foreground (black/white) for text drawn on top of [background].
Color contrastOn(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}
