// lib/src/ui/theme/typography.dart

import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Brand typography for the LeakRadar in-app UX.
///
/// All getters return a [TextStyle] pre-wired with the correct font family
/// and sensible defaults. Callers may `.copyWith(...)` to adjust size/colour.
abstract final class LeakRadarText {
  // ── Space Grotesk ─────────────────────────────────────────────────────────

  /// Section / card titles — Space Grotesk Bold.
  static TextStyle get title => GoogleFonts.spaceGrotesk(
        fontWeight: FontWeight.w700,
        color: LeakRadarColors.text100,
        fontSize: 16,
        height: 1.25,
      );

  /// Numeric metric displays — Space Grotesk SemiBold.
  static TextStyle get metric => GoogleFonts.spaceGrotesk(
        fontWeight: FontWeight.w600,
        color: LeakRadarColors.text100,
        fontSize: 28,
        height: 1.1,
      );

  // ── JetBrains Mono ────────────────────────────────────────────────────────

  /// Code / class-name snippets — JetBrains Mono Regular.
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontWeight: FontWeight.w400,
        color: LeakRadarColors.text80,
        fontSize: 13,
        height: 1.5,
      );

  /// Uppercase labels and section dividers — JetBrains Mono Medium.
  ///
  /// Apply `toUpperCase()` on the string side; letter-spacing mimics the
  /// all-caps feel without a CSS `text-transform` equivalent.
  static TextStyle get label => GoogleFonts.jetBrainsMono(
        fontWeight: FontWeight.w500,
        color: LeakRadarColors.text40,
        fontSize: 11,
        letterSpacing: 0.08 * 11, // ≈ 0.08em
        height: 1.4,
      );

  /// Small severity pill text — JetBrains Mono Medium.
  static TextStyle get severityTag => GoogleFonts.jetBrainsMono(
        fontWeight: FontWeight.w500,
        color: LeakRadarColors.text100,
        fontSize: 10,
        letterSpacing: 0.04 * 10,
        height: 1.2,
      );

  // ── Hanken Grotesk ────────────────────────────────────────────────────────

  /// Body / description copy — Hanken Grotesk Regular.
  static TextStyle get body => GoogleFonts.hankenGrotesk(
        fontWeight: FontWeight.w400,
        color: LeakRadarColors.text80,
        fontSize: 14,
        height: 1.55,
      );
}
