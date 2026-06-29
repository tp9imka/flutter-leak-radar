// lib/src/tokens/density.dart

import 'package:flutter/painting.dart';

/// Spacing, sizing, and radius constants for the Flutter Radar
/// design system.
///
/// These match the density targets from the design handoff: tight
/// table rows (~34–40px), minimal chrome, and small tag/icon sizes.
abstract final class RadarDensity {
  // ── Row / list ────────────────────────────────────────────────────────────

  /// Minimum row height for dense table rows (34px).
  static const double rowHeightMin = 34.0;

  /// Standard row height for table / list rows (38px).
  static const double rowHeight = 38.0;

  /// Maximum row height for wide rows (40px).
  static const double rowHeightMax = 40.0;

  /// Vertical padding inside a table row (8px).
  static const double rowVPad = 8.0;

  /// Horizontal padding inside a table row (10px).
  static const double rowHPad = 10.0;

  /// Border radius for list / table rows (11px).
  static const BorderRadius rowRadius = BorderRadius.all(Radius.circular(11));

  // ── Tags / pills ──────────────────────────────────────────────────────────

  /// Horizontal padding inside a tag pill (6px).
  static const double tagHPad = 6.0;

  /// Vertical padding inside a tag pill (3px).
  static const double tagVPad = 3.0;

  /// Border radius for tag pills (5px — mid of the 4–6 range).
  static const BorderRadius tagRadius = BorderRadius.all(Radius.circular(5));

  // ── Input fields / metric tiles ───────────────────────────────────────────

  /// Border radius for input fields and metric tiles (8px).
  static const BorderRadius inputRadius = BorderRadius.all(Radius.circular(8));

  // ── Icon buttons ──────────────────────────────────────────────────────────

  /// Icon button target size (31×31px).
  static const double iconButtonSize = 31.0;

  /// Border radius for icon buttons (8px).
  static const BorderRadius iconButtonRadius = BorderRadius.all(
    Radius.circular(8),
  );

  // ── Sparkline ─────────────────────────────────────────────────────────────

  /// Default sparkline width (52px).
  static const double sparklineWidth = 52.0;

  /// Default sparkline height (16px).
  static const double sparklineHeight = 16.0;

  // ── Hairline ──────────────────────────────────────────────────────────────

  /// Standard 1px hairline separator thickness.
  static const double hairline = 1.0;

  // ── Miscellaneous ─────────────────────────────────────────────────────────

  /// Overlay badge border radius (13px).
  static const double badgeRadius = 13.0;

  /// Bottom sheet top radius (20px).
  static const double sheetRadius = 20.0;

  /// Left severity bar width on list rows (4px).
  static const double severityBarWidth = 4.0;

  /// Chip horizontal padding (10px).
  static const double chipHPad = 10.0;

  /// Chip vertical padding (6px).
  static const double chipVPad = 6.0;

  /// Chip border radius (20px — fully rounded).
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(20));
}
