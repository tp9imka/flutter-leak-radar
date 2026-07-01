// lib/src/widgets/radar_filter_chip.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';
import '../tokens/typography.dart';

/// A quick-filter chip for Radar list views.
///
/// When [selected] is `true` the chip fills with [RadarColors.accentSubtle]
/// and uses an accent border, signaling the active filter. Tapping calls
/// [onSelected]; the parent manages the [selected] state.
///
/// Used for "all · not disposed · errors-only · hot/dup · growth" strips.
class RadarFilterChip extends StatelessWidget {
  const RadarFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  /// Label text for this chip.
  final String label;

  /// Whether this chip is the active/selected filter.
  final bool selected;

  /// Called when the chip is tapped.
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? RadarColors.accent : RadarColors.hairline08;
    final bgColor = selected ? RadarColors.accentSubtle : RadarColors.bgInput;
    final textColor = selected ? RadarColors.accent : RadarColors.text60;

    return Material(
      color: bgColor,
      borderRadius: RadarDensity.chipRadius,
      child: InkWell(
        borderRadius: RadarDensity.chipRadius,
        onTap: onSelected,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: RadarDensity.chipRadius,
            border: Border.all(
              color: borderColor,
              width: RadarDensity.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RadarDensity.chipHPad,
              vertical: RadarDensity.chipVPad,
            ),
            child: Text(
              label,
              style: RadarTypography.monoLabel.copyWith(color: textColor),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      ),
    );
  }
}
