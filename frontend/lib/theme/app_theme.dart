import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Builds the two [ThemeData] instances for QuietPass. Screens do not read from
/// here; they read semantic tokens through [AppColors]. This file only assembles
/// Material's own surfaces, the text scale, and default component styling so the
/// framework widgets match the foundation.
abstract final class AppTheme {
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);
  static ThemeData get light => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    // Single family, disciplined scale. Sizes match the approved foundation;
    // heights and weights kept consistent so the app reads as one product.
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: c.ink, displayColor: c.ink)
        .copyWith(
          displaySmall: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            height: 1.06,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: c.ink,
          ),
          titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: c.ink,
          ),
          titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
          bodyLarge: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            height: 1.5,
            fontWeight: FontWeight.w400,
            color: c.ink,
          ),
          bodyMedium: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w400,
            color: c.ink2,
          ),
          labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: c.ink2,
          ),
          bodySmall: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w500,
            color: c.ink3,
          ),
        );

    final scheme = (brightness == Brightness.dark
            ? const ColorScheme.dark()
            : const ColorScheme.light())
        .copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      surface: c.surface,
      onSurface: c.ink,
      outline: c.line2,
      brightness: brightness,
    );

    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      colorScheme: scheme,
      textTheme: textTheme,
      dividerColor: c.line,
      extensions: <ThemeExtension<dynamic>>[c],
      splashFactory: InkRipple.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }
}
