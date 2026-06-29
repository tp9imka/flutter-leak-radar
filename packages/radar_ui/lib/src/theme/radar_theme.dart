// lib/src/theme/radar_theme.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';
import '../tokens/typography.dart';

/// Returns a [ThemeData] wired to the Flutter Radar dark design system.
///
/// Intended as the root theme for any Radar surface. Sub-surfaces may
/// call `theme.copyWith(...)` to override individual components.
ThemeData radarDarkTheme() {
  const colorScheme = ColorScheme.dark(
    surface: RadarColors.bgSurface,
    onSurface: RadarColors.text100,
    primary: RadarColors.accent,
    onPrimary: Color(0xFF001a0d),
    error: RadarColors.critical,
    onError: RadarColors.text100,
    outline: RadarColors.hairline08,
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: RadarColors.bgPage,
    canvasColor: RadarColors.bgPage,

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: RadarColors.bgPanel,
      foregroundColor: RadarColors.text100,
      titleTextStyle: RadarTypography.appBarTitle,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
    ),

    // Chips (filter chips)
    chipTheme: ChipThemeData(
      backgroundColor: RadarColors.bgInput,
      selectedColor: RadarColors.accentSubtle,
      side: const BorderSide(
        color: RadarColors.hairline08,
        width: RadarDensity.hairline,
      ),
      labelStyle: RadarTypography.monoLabel,
      labelPadding: const EdgeInsets.symmetric(
        horizontal: RadarDensity.chipHPad,
        vertical: RadarDensity.chipVPad,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: RadarDensity.chipRadius,
      ),
    ),

    // Input fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RadarColors.bgInput,
      hintStyle: RadarTypography.monoInput.copyWith(color: RadarColors.text25),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderSide: const BorderSide(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(
          color: RadarColors.accent,
          width: RadarDensity.hairline,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
    ),

    // Dividers
    dividerTheme: const DividerThemeData(
      color: RadarColors.hairline08,
      thickness: RadarDensity.hairline,
      space: 0,
    ),

    // Typography defaults
    textTheme: TextTheme(
      bodyLarge: RadarTypography.body,
      bodyMedium: RadarTypography.body,
      bodySmall: RadarTypography.caption,
      labelSmall: RadarTypography.monoLabel,
      titleMedium: RadarTypography.appBarTitle,
      displayLarge: RadarTypography.metricHero,
    ),

    useMaterial3: true,
  );
}
