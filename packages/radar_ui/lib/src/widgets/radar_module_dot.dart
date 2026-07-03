// lib/src/widgets/radar_module_dot.dart

import 'package:flutter/widgets.dart';

import '../tokens/typography.dart';

/// A small rounded-square color swatch for a category/module.
///
/// Optionally followed by a mono [label] (used for the table's module
/// color-tags and the legend).
class RadarModuleDot extends StatelessWidget {
  const RadarModuleDot({
    super.key,
    required this.color,
    this.label,
    this.size = 8,
  });

  /// Fill color of the swatch.
  final Color color;

  /// Optional mono label rendered to the right of the swatch.
  final String? label;

  /// Width and height of the swatch, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(Radius.circular(2)),
        ),
      ),
    );

    final label = this.label;
    if (label == null) return box;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        box,
        const SizedBox(width: 4),
        Text(label, style: RadarTypography.monoTag),
      ],
    );
  }
}
