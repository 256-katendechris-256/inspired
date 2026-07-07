import 'package:flutter/material.dart';

import 'brand.dart';

/// Inter-based type scale, tuned for a clean, modern product UI: tighter
/// letter-spacing on large text, comfortable line-heights, clear weight steps.
TextTheme _textTheme() {
  TextStyle s(
    double size,
    FontWeight weight, {
    double height = 1.3,
    double spacing = 0,
    Color color = Brand.ink,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: spacing,
    color: color,
  );

  return TextTheme(
    displaySmall: s(34, FontWeight.w700, height: 1.08, spacing: -0.8),
    headlineLarge: s(28, FontWeight.w700, height: 1.12, spacing: -0.6),
    headlineMedium: s(23, FontWeight.w700, height: 1.18, spacing: -0.4),
    titleLarge: s(20, FontWeight.w700, height: 1.25, spacing: -0.2),
    titleMedium: s(16, FontWeight.w600, height: 1.3, spacing: -0.1),
    titleSmall: s(14, FontWeight.w600, height: 1.3),
    bodyLarge: s(16, FontWeight.w400, height: 1.45),
    bodyMedium: s(14, FontWeight.w400, height: 1.45),
    bodySmall: s(12.5, FontWeight.w400, height: 1.4, color: Brand.slate),
    labelLarge: s(14, FontWeight.w600, height: 1.2, spacing: 0.1),
    labelMedium: s(12, FontWeight.w600, height: 1.2, spacing: 0.2),
    labelSmall: s(11, FontWeight.w600, height: 1.2, spacing: 0.4, color: Brand.mute),
  );
}

/// A clean, white, productivity-first light theme on the Inspire Africa Group
/// palette, set in Inter. White surfaces, green primary, hairline borders.
ThemeData _build() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Brand.green,
        brightness: Brightness.light,
      ).copyWith(
        primary: Brand.green,
        secondary: Brand.blue,
        surface: Colors.white,
        onSurface: Brand.ink,
        surfaceContainerHighest: Brand.surfaceAlt,
        outlineVariant: Brand.line,
        error: Brand.red,
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.canvas,
    fontFamily: 'Inter',
    textTheme: _textTheme(),
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _textTheme().titleLarge,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Brand.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.green, width: 2),
      ),
      floatingLabelStyle: const TextStyle(color: Brand.green),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Brand.green,
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: const TextStyle(
        fontFamily: 'Inter',
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
    ),
    dividerTheme: const DividerThemeData(color: Brand.line, thickness: 1),
  );
}

final ThemeData inspiredLightTheme = _build();
