// lib/src/ui/theme/typography.dart

import 'package:flutter/widgets.dart';

import 'colors.dart';

const String _fontPkg = 'flutter_leak_radar';

TextStyle _font(
  String family, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  FontStyle? fontStyle,
  TextDecoration? decoration,
}) {
  final w = fontWeight ?? FontWeight.w400;
  return TextStyle(
    fontFamily: family,
    package: _fontPkg,
    fontSize: fontSize,
    fontWeight: w,
    fontVariations: [FontVariation('wght', w.value.toDouble())],
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontStyle: fontStyle,
    decoration: decoration,
  );
}

TextStyle monoFont({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  FontStyle? fontStyle,
  TextDecoration? decoration,
}) => _font(
  'JetBrainsMono',
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontStyle: fontStyle,
  decoration: decoration,
);

TextStyle displayFont({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  FontStyle? fontStyle,
  TextDecoration? decoration,
}) => _font(
  'SpaceGrotesk',
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontStyle: fontStyle,
  decoration: decoration,
);

TextStyle bodyFont({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  FontStyle? fontStyle,
  TextDecoration? decoration,
}) => _font(
  'HankenGrotesk',
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontStyle: fontStyle,
  decoration: decoration,
);

/// Brand typography for the LeakRadar in-app UX.
///
/// All getters return a [TextStyle] pre-wired with the correct font family
/// and sensible defaults. Callers may `.copyWith(...)` to adjust size/colour.
abstract final class LeakRadarText {
  // ── Space Grotesk ─────────────────────────────────────────────────────────

  static TextStyle get title => displayFont(
    fontWeight: FontWeight.w700,
    color: LeakRadarColors.text100,
    fontSize: 16,
    height: 1.25,
  );

  static TextStyle get metric => displayFont(
    fontWeight: FontWeight.w600,
    color: LeakRadarColors.text100,
    fontSize: 28,
    height: 1.1,
  );

  // ── JetBrains Mono ────────────────────────────────────────────────────────

  static TextStyle get mono => monoFont(
    fontWeight: FontWeight.w400,
    color: LeakRadarColors.text80,
    fontSize: 13,
    height: 1.5,
  );

  /// Apply `toUpperCase()` on the string side; letter-spacing mimics all-caps feel.
  static TextStyle get label => monoFont(
    fontWeight: FontWeight.w500,
    color: LeakRadarColors.text40,
    fontSize: 11,
    letterSpacing: 0.08 * 11,
    height: 1.4,
  );

  static TextStyle get severityTag => monoFont(
    fontWeight: FontWeight.w500,
    color: LeakRadarColors.text100,
    fontSize: 10,
    letterSpacing: 0.04 * 10,
    height: 1.2,
  );

  // ── Hanken Grotesk ────────────────────────────────────────────────────────

  static TextStyle get body => bodyFont(
    fontWeight: FontWeight.w400,
    color: LeakRadarColors.text80,
    fontSize: 14,
    height: 1.55,
  );
}
