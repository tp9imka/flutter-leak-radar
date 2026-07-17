// lib/src/tokens/origin.dart

import 'package:flutter/painting.dart';

import 'colors.dart';

/// Ownership buckets for an attributed leak class.
///
/// Mirrors `leak_graph`'s `ClassOrigin` without depending on it — radar_ui
/// stays dependency-clean; the workbench maps `ClassOrigin` onto this enum.
enum RadarOrigin { project, dependency, framework, sdk, unknown }

/// Per-[RadarOrigin] color and label lookup.
///
/// Shared by every ownership surface (chips, group headers, the native
/// module legend) so the suite renders one consistent ownership palette.
extension RadarOriginX on RadarOrigin {
  /// The ownership color for this origin.
  ///
  /// [RadarOrigin.project] is violet, the "free" hue — deliberately not
  /// [RadarColors.accent], which means healthy/negative-delta everywhere
  /// else in the suite. Dependency reads as a strong neutral; framework
  /// and sdk are progressively more muted; unknown is the most muted.
  Color get color => switch (this) {
    RadarOrigin.project => RadarColors.violet,
    RadarOrigin.dependency => RadarColors.text80,
    RadarOrigin.framework => RadarColors.text40,
    RadarOrigin.sdk => RadarColors.text25,
    RadarOrigin.unknown => RadarColors.text15,
  };

  /// The display label for this origin (`'yours'` for project code).
  String get label => switch (this) {
    RadarOrigin.project => 'yours',
    RadarOrigin.dependency => 'dependency',
    RadarOrigin.framework => 'framework',
    RadarOrigin.sdk => 'sdk',
    RadarOrigin.unknown => '—',
  };
}

/// Static [RadarOrigin] color/label lookup for call sites that only have
/// the enum value in hand (e.g. the native module palette).
///
/// Prefer [RadarOriginX.color] / [RadarOriginX.label] when the extension
/// import is already in scope.
abstract final class OriginTokens {
  /// The ownership color for [origin]. See [RadarOriginX.color].
  static Color color(RadarOrigin origin) => origin.color;

  /// The display label for [origin]. See [RadarOriginX.label].
  static String label(RadarOrigin origin) => origin.label;
}
