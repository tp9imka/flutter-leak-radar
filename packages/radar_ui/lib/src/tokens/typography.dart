// lib/src/tokens/typography.dart

import 'package:flutter/painting.dart';

import 'colors.dart';

const String _pkg = 'radar_ui';

TextStyle _font(
  String family, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) {
  final w = fontWeight ?? FontWeight.w400;
  return TextStyle(
    fontFamily: family,
    package: _pkg,
    fontSize: fontSize,
    fontWeight: w,
    fontVariations: [FontVariation('wght', w.value.toDouble())],
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
  );
}

/// Returns a JetBrains Mono [TextStyle] with tabular figures enabled.
///
/// Tabular figures are mandatory for all numeric / code / tag text
/// so that table columns align correctly.
TextStyle radarMonoStyle({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
}) => _font(
      'JetBrainsMono',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Returns a Space Grotesk [TextStyle] (headlines and big metric values).
TextStyle radarDisplayStyle({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
}) => _font(
      'SpaceGrotesk',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );

/// Returns a Hanken Grotesk [TextStyle] (body and labels).
TextStyle radarBodyStyle({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
}) => _font(
      'HankenGrotesk',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );

/// Pre-built [TextStyle] constants for common Radar text roles.
///
/// These cover the roles called out in the design handoff.
/// For custom variants call [radarMonoStyle], [radarDisplayStyle],
/// or [radarBodyStyle] directly.
abstract final class RadarTypography {
  // ── Space Grotesk (headlines / metric values) ─────────────────────────────

  /// App-bar title: Space Grotesk 600 / 15.5px.
  static TextStyle get appBarTitle => radarDisplayStyle(
        fontWeight: FontWeight.w600,
        fontSize: 15.5,
        color: RadarColors.text100,
        height: 1.25,
      );

  /// Large metric headline: Space Grotesk 600 / 38px (Startup "first frame").
  static TextStyle get metricHero => radarDisplayStyle(
        fontWeight: FontWeight.w600,
        fontSize: 38,
        color: RadarColors.accent,
        height: 1.1,
      );

  /// Tile metric value: Space Grotesk 600 / 28px.
  static TextStyle get metricValue => radarDisplayStyle(
        fontWeight: FontWeight.w600,
        fontSize: 28,
        color: RadarColors.text100,
        height: 1.1,
      );

  // ── JetBrains Mono (numbers / code / tags / table data) ──────────────────

  /// Row class name / operation name: mono 13px (with tabular figures).
  static TextStyle get monoBody => radarMonoStyle(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        color: RadarColors.text100,
        height: 1.5,
      );

  /// Right-aligned numeric column value: mono 12.5px 600.
  static TextStyle get monoNumber => radarMonoStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12.5,
        color: RadarColors.text100,
        height: 1.4,
      );

  /// Tag/pill label: mono 9–10px (apply `.toUpperCase()` in the widget).
  static TextStyle get monoTag => radarMonoStyle(
        fontWeight: FontWeight.w500,
        fontSize: 9.5,
        color: RadarColors.text100,
        height: 1.2,
        letterSpacing: 0.04 * 9.5,
      );

  /// Label / caption: mono 9.5–11px, dimmed.
  static TextStyle get monoLabel => radarMonoStyle(
        fontWeight: FontWeight.w400,
        fontSize: 10.5,
        color: RadarColors.text40,
        height: 1.4,
        letterSpacing: 0.04 * 10.5,
      );

  /// Search / filter field input text: mono 13px.
  static TextStyle get monoInput => radarMonoStyle(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        color: RadarColors.text100,
        height: 1.5,
      );

  /// Code block / retaining-path text: mono 12px.
  static TextStyle get monoCode => radarMonoStyle(
        fontWeight: FontWeight.w400,
        fontSize: 12,
        color: RadarColors.text80,
        height: 1.6,
      );

  // ── Hanken Grotesk (body / UI copy) ──────────────────────────────────────

  /// General body text: Hanken Grotesk 400 / 14px.
  static TextStyle get body => radarBodyStyle(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        color: RadarColors.text80,
        height: 1.55,
      );

  /// Small caption / sub-label: Hanken Grotesk 400 / 12px.
  static TextStyle get caption => radarBodyStyle(
        fontWeight: FontWeight.w400,
        fontSize: 12,
        color: RadarColors.text40,
        height: 1.4,
      );
}
