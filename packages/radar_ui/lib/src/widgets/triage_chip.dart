// lib/src/widgets/triage_chip.dart

import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import 'radar_tag.dart';

/// Display-only cross-session identity for a leak cluster/row.
///
/// Owned by radar_ui (`fresh` avoids the `new` keyword). The workbench
/// maps its persisted `TriageStatus` (fresh/known/acknowledged, with GONE
/// computed rather than stored) onto this enum — do not redefine it there.
enum TriageDisplay { fresh, known, acknowledged, gone }

/// Color and rendered label for a [TriageDisplay] value.
extension _TriageDisplayX on TriageDisplay {
  /// GONE renders in the accent family — a fixed leak is a positive
  /// outcome, the same signal as the healthy severity level.
  Color get color => switch (this) {
    TriageDisplay.fresh => RadarColors.info,
    TriageDisplay.known => RadarColors.text50,
    TriageDisplay.acknowledged => RadarColors.text40,
    TriageDisplay.gone => RadarColors.accent,
  };

  String get rendered => switch (this) {
    TriageDisplay.fresh => 'NEW',
    TriageDisplay.known => 'KNOWN',
    TriageDisplay.acknowledged => 'ACK',
    TriageDisplay.gone => 'GONE',
  };
}

/// A compact cross-session status pill (NEW / KNOWN / ACK / GONE).
///
/// Built on [RadarTag].
class TriageChip extends StatelessWidget {
  const TriageChip({super.key, required this.display});

  /// Which cross-session bucket this row currently falls into.
  final TriageDisplay display;

  @override
  Widget build(BuildContext context) =>
      RadarTag(label: display.rendered, color: display.color);
}
