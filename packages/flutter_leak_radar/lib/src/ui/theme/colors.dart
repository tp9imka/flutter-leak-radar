// lib/src/ui/theme/colors.dart

import 'package:flutter/painting.dart';

/// Dark-mode color palette for the LeakRadar in-app UX.
///
/// All values are const. Use these tokens instead of raw hex literals
/// anywhere inside the theme or UI files.
abstract final class LeakRadarColors {
  // ── Page / surface backgrounds ──────────────────────────────────────────
  static const Color pageBg = Color(0xFF0a0d0e);
  static const Color hostAppBg = Color(0xFF0f1316);
  static const Color cardBg = Color(0xFF0e1316);
  static const Color appBarBg = Color(0xFF0c1012);
  static const Color codePreviewBg = Color(0xFF06090a);

  // ── Accent ───────────────────────────────────────────────────────────────
  static const Color accent = Color(0xFF2fe39b);
  static const Color accentHover = Color(0xFF52f0b0);

  // ── Severity ─────────────────────────────────────────────────────────────
  static const Color severityCritical = Color(0xFFff5d6c);
  static const Color severityWarning = Color(0xFFf5b54a);
  static const Color severityInfo = Color(0xFF5ad1e6);

  // ── Text scale (light → dim) ─────────────────────────────────────────────
  static const Color text100 = Color(0xFFe7eef0);
  static const Color text80 = Color(0xFFcdd6da);
  static const Color text60 = Color(0xFFa7b6bc);
  static const Color text40 = Color(0xFF7d8e94);
  static const Color text25 = Color(0xFF5f7178);
  static const Color text15 = Color(0xFF4a5a60);
  static const Color text10 = Color(0xFF3d4a4f);

  // ── Hairline borders (white with alpha) ───────────────────────────────────
  static const Color border05 = Color.fromRGBO(255, 255, 255, 0.05);
  static const Color border08 = Color.fromRGBO(255, 255, 255, 0.08);
  static const Color border10 = Color.fromRGBO(255, 255, 255, 0.10);
  static const Color border12 = Color.fromRGBO(255, 255, 255, 0.12);
}
