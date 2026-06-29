// lib/src/widgets/radar_metric_tile.dart

import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';
import '../tokens/severity.dart';
import '../tokens/typography.dart';

/// A label + big-value display tile for the Flutter Radar design system.
///
/// The [value] is rendered in the color derived from [severity], or in
/// [color] if provided, or in [RadarColors.text100] as the neutral default.
///
/// Used in stat grids (e.g., "Live now · 42", "Jank % · 3.2%").
class RadarMetricTile extends StatelessWidget {
  const RadarMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.severity,
    this.color,
  });

  /// Caption displayed above the value (e.g., "Live now", "Net growth").
  final String label;

  /// The metric value string (e.g., "42", "3.2%", "N/A").
  final String value;

  /// Optional severity level; determines [value] text color.
  final RadarSeverity? severity;

  /// Explicit value text color; takes precedence over [severity].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final valueColor = color ?? severity?.color ?? RadarColors.text100;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: RadarTypography.monoLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: RadarTypography.metricValue.copyWith(color: valueColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
