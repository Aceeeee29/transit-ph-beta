import 'package:flutter/material.dart';

/// The app's surface and text colors, one set for light and one for dark.
class AppPalette {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accentSoft,
  });

  /// Page backgrounds.
  final Color bg;

  /// Cards, sheets, dialogs and bars.
  final Color surface;

  /// Fields, chips and tinted panels.
  final Color surfaceAlt;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  /// Tinted backgrounds of selected things.
  final Color accentSoft;

  static const light = AppPalette(
    bg: Color(0xFFF4F8FF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEAF2FF),
    border: Color(0xFFD4E4F7),
    textPrimary: Color(0xFF0F1D35),
    textSecondary: Color(0xFF7A92B2),
    accentSoft: Color(0x1A0B8FD6),
  );

  /// Blue-grays that sit with the night map.
  static const dark = AppPalette(
    bg: Color(0xFF10161F),
    surface: Color(0xFF1A2230),
    surfaceAlt: Color(0xFF222C3C),
    border: Color(0xFF2C3849),
    textPrimary: Color(0xFFE6EDF5),
    textSecondary: Color(0xFF8A9BB0),
    accentSoft: Color(0x330B8FD6),
  );
}

/// Brand colors, plus the current [AppPalette] (Settings > Appearance).
/// The blue is a deepened version of the logo's sky-blue so white text on
/// it stays readable; it reads well on the dark palette too, so it is the
/// same in both.
class AppColors {
  AppColors._();

  /// Switched by the app (main.dart) when the appearance changes, which
  /// then redraws every screen.
  static AppPalette palette = AppPalette.light;

  static bool get isDark => identical(palette, AppPalette.dark);

  static Color get bg => palette.bg;
  static Color get surface => palette.surface;
  static Color get surfaceAlt => palette.surfaceAlt;
  static Color get border => palette.border;
  static Color get textPrimary => palette.textPrimary;
  static Color get textSecondary => palette.textSecondary;

  /// Buttons, links and selected states.
  static const accent = Color(0xFF0B8FD6);
  static Color get accentSoft => palette.accentSoft;

  /// Primary buttons.
  static const buttonGradient = [Color(0xFF0B8FD6), Color(0xFF2BB5F0)];

  /// A tinted panel (tips, warnings): the color's palest shade by day, a
  /// faint wash of it in dark.
  static Color tint(MaterialColor color) =>
      isDark ? color.withValues(alpha: 0.14) : color.shade50;

  /// The border of a [tint] panel.
  static Color tintBorder(MaterialColor color, {int shade = 200}) =>
      isDark ? color.withValues(alpha: 0.4) : color[shade]!;

  /// Text on a [tint] panel: a deep shade by day, a light one in dark.
  static Color tintText(MaterialColor color, {int shade = 700}) =>
      isDark ? color.shade200 : color[shade]!;
}
