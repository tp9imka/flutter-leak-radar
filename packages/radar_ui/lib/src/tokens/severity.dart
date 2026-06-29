// lib/src/tokens/severity.dart

import 'package:flutter/painting.dart';

import 'colors.dart';

/// The four severity levels used across all Radar surfaces.
///
/// Maps directly onto the design spine:
/// critical → `#ff5d6c`, warning → `#f5b54a`,
/// info → `#5ad1e6`, healthy → `#2fe39b`.
enum RadarSeverity { critical, warning, info, healthy }

/// Per-severity derived design tokens.
///
/// Provides the tinted backgrounds and borders used for tags and
/// table rows so callers don't have to recompute rgba values.
final class SeverityTokens {
  const SeverityTokens({
    required this.text,
    required this.tagBg,
    required this.tagBorder,
    required this.rowBg,
    required this.rowBorder,
  });

  /// Foreground color for severity text and icons.
  final Color text;

  /// Background fill for a severity tag / pill.
  final Color tagBg;

  /// Border for a severity tag / pill.
  final Color tagBorder;

  /// Subtle tinted background for a table row.
  final Color rowBg;

  /// Border for a tinted table row.
  final Color rowBorder;
}

const _criticalTokens = SeverityTokens(
  text: RadarColors.critical,
  tagBg: Color.fromRGBO(255, 93, 108, 0.12),
  tagBorder: Color.fromRGBO(255, 93, 108, 0.30),
  rowBg: Color.fromRGBO(255, 93, 108, 0.05),
  rowBorder: Color.fromRGBO(255, 93, 108, 0.18),
);

const _warningTokens = SeverityTokens(
  text: RadarColors.warning,
  tagBg: Color.fromRGBO(245, 181, 74, 0.12),
  tagBorder: Color.fromRGBO(245, 181, 74, 0.30),
  rowBg: Color.fromRGBO(245, 181, 74, 0.05),
  rowBorder: Color.fromRGBO(245, 181, 74, 0.18),
);

const _infoTokens = SeverityTokens(
  text: RadarColors.info,
  tagBg: Color.fromRGBO(90, 209, 230, 0.10),
  tagBorder: Color.fromRGBO(90, 209, 230, 0.25),
  rowBg: Color.fromRGBO(90, 209, 230, 0.04),
  rowBorder: Color.fromRGBO(90, 209, 230, 0.15),
);

const _healthyTokens = SeverityTokens(
  text: RadarColors.accent,
  tagBg: Color.fromRGBO(47, 227, 155, 0.12),
  tagBorder: Color.fromRGBO(47, 227, 155, 0.30),
  rowBg: Color.fromRGBO(47, 227, 155, 0.05),
  rowBorder: Color.fromRGBO(47, 227, 155, 0.18),
);

/// Convenience extensions on [RadarSeverity].
extension RadarSeverityX on RadarSeverity {
  /// The primary foreground color for this severity level.
  Color get color => switch (this) {
        RadarSeverity.critical => RadarColors.critical,
        RadarSeverity.warning => RadarColors.warning,
        RadarSeverity.info => RadarColors.info,
        RadarSeverity.healthy => RadarColors.accent,
      };

  /// Full set of derived design tokens for tags and rows.
  SeverityTokens get tokens => switch (this) {
        RadarSeverity.critical => _criticalTokens,
        RadarSeverity.warning => _warningTokens,
        RadarSeverity.info => _infoTokens,
        RadarSeverity.healthy => _healthyTokens,
      };
}

/// Returns the primary foreground [Color] for the given [severity].
///
/// Delegates to [RadarSeverityX.color]; prefer calling `.color` directly
/// on the enum value when it is already in scope.
Color radarSeverityColor(RadarSeverity severity) => severity.color;
