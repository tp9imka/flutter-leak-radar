// lib/src/ui/theme/severity_tokens.dart

import 'package:flutter/painting.dart';

import '../../model/leak_kind.dart';
import 'colors.dart';

/// Per-severity design tokens: text, tag, and row colours.
///
/// Use [severityTokens] to look up the right set for a [LeakSeverity] value.
final class SeverityTokens {
  const SeverityTokens({
    required this.text,
    required this.tagBg,
    required this.tagBorder,
    required this.rowBg,
    required this.rowBorder,
  });

  /// Foreground colour for severity text / icon.
  final Color text;

  /// Background fill for the severity pill/tag.
  final Color tagBg;

  /// Border colour for the severity pill/tag.
  final Color tagBorder;

  /// Subtle tinted background for a table/list row.
  final Color rowBg;

  /// Border colour for a table/list row.
  final Color rowBorder;
}

// ── Token maps ────────────────────────────────────────────────────────────────

const _critical = SeverityTokens(
  text: LeakRadarColors.severityCritical,
  tagBg: Color.fromRGBO(255, 93, 108, 0.12),
  tagBorder: Color.fromRGBO(255, 93, 108, 0.30),
  rowBg: Color.fromRGBO(255, 93, 108, 0.05),
  rowBorder: Color.fromRGBO(255, 93, 108, 0.18),
);

const _warning = SeverityTokens(
  text: LeakRadarColors.severityWarning,
  tagBg: Color.fromRGBO(245, 181, 74, 0.12),
  tagBorder: Color.fromRGBO(245, 181, 74, 0.30),
  rowBg: Color.fromRGBO(245, 181, 74, 0.05),
  rowBorder: Color.fromRGBO(245, 181, 74, 0.18),
);

const _info = SeverityTokens(
  text: LeakRadarColors.severityInfo,
  tagBg: Color.fromRGBO(90, 209, 230, 0.10),
  tagBorder: Color.fromRGBO(90, 209, 230, 0.25),
  rowBg: Color.fromRGBO(90, 209, 230, 0.04),
  rowBorder: Color.fromRGBO(90, 209, 230, 0.15),
);

/// Returns the [SeverityTokens] for the given [severity].
SeverityTokens severityTokens(LeakSeverity severity) {
  return switch (severity) {
    LeakSeverity.critical => _critical,
    LeakSeverity.warning => _warning,
    LeakSeverity.info => _info,
  };
}
