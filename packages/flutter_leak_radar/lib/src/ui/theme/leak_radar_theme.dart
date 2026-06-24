// lib/src/ui/theme/leak_radar_theme.dart

import 'package:flutter/painting.dart';

import 'colors.dart';

export 'colors.dart';
export 'severity_tokens.dart';
export 'typography.dart';
export 'radar_glyph.dart';

/// Common sizing and decoration constants for icon buttons.
abstract final class LeakRadarDimens {
  /// Square side length for icon-button hit targets.
  static const double iconButtonSize = 34.0;

  /// Corner radius for icon-button containers.
  static const double iconButtonRadius = 9.0;

  /// Background fill for icon buttons (subtle translucent tint).
  static const Color iconButtonBg = Color.fromRGBO(255, 255, 255, 0.05);

  /// Border colour for icon buttons.
  static const Color iconButtonBorder = Color.fromRGBO(255, 255, 255, 0.10);
}

/// Miscellaneous layout and decoration constants shared across LeakRadar UI.
abstract final class LeakRadarTheme {
  // ── Card / panel ────────────────────────────────────────────────────────────
  static const double cardRadius = 12.0;
  static const double cardPadding = 16.0;

  // ── Tag pill ─────────────────────────────────────────────────────────────────
  static const double tagRadius = 5.0;
  static const double tagPaddingH = 6.0;
  static const double tagPaddingV = 2.0;

  // ── Layout ───────────────────────────────────────────────────────────────────
  static const double contentPaddingH = 16.0;
  static const double contentPaddingV = 12.0;
  static const double rowHeight = 48.0;

  // ── Icon sizes ───────────────────────────────────────────────────────────────
  static const double iconSm = 16.0;
  static const double iconMd = 20.0;
  static const double iconLg = 24.0;

  // ── Border ───────────────────────────────────────────────────────────────────
  static const Color divider = LeakRadarColors.border08;

  // ── Elevation / shadow ───────────────────────────────────────────────────────
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
