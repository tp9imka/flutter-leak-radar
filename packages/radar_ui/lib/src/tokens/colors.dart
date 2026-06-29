// lib/src/tokens/colors.dart

import 'package:flutter/painting.dart';

/// Complete dark-mode color palette for the Flutter Radar design system.
///
/// Use these named constants wherever raw hex values would otherwise appear.
/// All values match the design handoff exactly.
abstract final class RadarColors {
  // ── Base backgrounds ──────────────────────────────────────────────────────

  /// Canvas background for the phone overlay (`#090c0d`).
  static const Color bgPhone = Color(0xFF090c0d);

  /// Page / shell background (`#0b0e10`).
  static const Color bgPage = Color(0xFF0b0e10);

  /// App bars, DevTools chrome (`#0c1012`).
  static const Color bgPanel = Color(0xFF0c1012);

  /// Cards, stat tiles (`#0e1316`).
  static const Color bgSurface = Color(0xFF0e1316);

  /// Inputs, segmented controls, raised surfaces (`#11171a`).
  static const Color bgInput = Color(0xFF11171a);

  /// Sticky table column headers (`#0b0f11`).
  static const Color bgTableHeader = Color(0xFF0b0f11);

  /// Retaining-path and stack-trace code blocks (`#06090a`).
  static const Color bgCode = Color(0xFF06090a);

  /// DevTools left rail (`#0a0e0f`).
  static const Color bgRail = Color(0xFF0a0e0f);

  // ── Accent ────────────────────────────────────────────────────────────────

  /// Primary accent: "connected", healthy, sort arrows, active chips.
  static const Color accent = Color(0xFF2fe39b);

  /// Slightly brighter accent for hover states.
  static const Color accentHover = Color(0xFF52f0b0);

  /// Semi-transparent accent fill (active chip background / rail selection).
  static const Color accentSubtle = Color.fromRGBO(47, 227, 155, 0.10);

  // ── Severity spine ────────────────────────────────────────────────────────

  /// Critical severity (`#ff5d6c`).
  static const Color critical = Color(0xFFff5d6c);

  /// Warning severity (`#f5b54a`).
  static const Color warning = Color(0xFFf5b54a);

  /// Info / secondary severity (`#5ad1e6`).
  static const Color info = Color(0xFF5ad1e6);

  // ── Text scale ────────────────────────────────────────────────────────────

  /// Primary text: values, names (`#e7eef0`).
  static const Color text100 = Color(0xFFe7eef0);

  /// Body, sub-metrics (`#cdd6da`).
  static const Color text80 = Color(0xFFcdd6da);

  /// Secondary body (`#a7b6bc`).
  static const Color text60 = Color(0xFFa7b6bc);

  /// Captions, inactive tabs (`#8fa0a6`).
  static const Color text50 = Color(0xFF8fa0a6);

  /// Inactive text, muted (`#7d8e94`).
  static const Color text40 = Color(0xFF7d8e94);

  /// Labels, units (`#5f7178`).
  static const Color text25 = Color(0xFF5f7178);

  /// Chrome, faint labels (`#4a5a60`).
  static const Color text15 = Color(0xFF4a5a60);

  /// Tree connectors, zeros (`#3d4a4f`).
  static const Color text10 = Color(0xFF3d4a4f);

  // ── Hairline borders (white-alpha) ────────────────────────────────────────

  /// Subtlest hairline (0.04 opacity).
  static const Color hairline04 = Color.fromRGBO(255, 255, 255, 0.04);

  /// Icon-button border (0.05 opacity).
  static const Color hairline05 = Color.fromRGBO(255, 255, 255, 0.05);

  /// Dividers (0.08 opacity).
  static const Color hairline08 = Color.fromRGBO(255, 255, 255, 0.08);

  /// Row separators (0.09 opacity).
  static const Color hairline09 = Color.fromRGBO(255, 255, 255, 0.09);

  /// Standard border (0.10 opacity).
  static const Color hairline10 = Color.fromRGBO(255, 255, 255, 0.10);

  /// Active tab border (0.12 opacity).
  static const Color hairline12 = Color.fromRGBO(255, 255, 255, 0.12);

  /// Icon-button background fill (0.05 opacity white).
  static const Color iconButtonBg = Color.fromRGBO(255, 255, 255, 0.05);

  /// Icon-button border (0.09 opacity white).
  static const Color iconButtonBorder = Color.fromRGBO(255, 255, 255, 0.09);

  /// Default row background (0.018 opacity white).
  static const Color rowBgDefault = Color.fromRGBO(255, 255, 255, 0.018);
}
