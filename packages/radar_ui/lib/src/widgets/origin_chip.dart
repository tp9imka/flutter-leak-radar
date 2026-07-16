// lib/src/widgets/origin_chip.dart

import 'package:flutter/widgets.dart';

import '../tokens/origin.dart';
import 'radar_tag.dart';

/// A compact ownership pill for a [RadarOrigin].
///
/// Built on [RadarTag]; color and label both come from [OriginTokens] so
/// chips, group headers, and the native module legend agree on one
/// ownership palette.
class OriginChip extends StatelessWidget {
  const OriginChip({super.key, required this.origin});

  /// The ownership bucket this chip represents.
  final RadarOrigin origin;

  @override
  Widget build(BuildContext context) => RadarTag(
    label: OriginTokens.label(origin).toUpperCase(),
    color: OriginTokens.color(origin),
  );
}
