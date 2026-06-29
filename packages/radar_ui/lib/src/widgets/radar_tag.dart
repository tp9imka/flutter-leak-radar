// lib/src/widgets/radar_tag.dart

import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';
import '../tokens/severity.dart';
import '../tokens/typography.dart';

/// A compact severity or kind pill for the Flutter Radar design system.
///
/// Renders an uppercase mono label with a tinted background and border
/// derived from [severity]. Pass [color] to override the text color
/// explicitly (used for kind tags that are not severity-mapped).
///
/// Spec: 9–10px mono, border radius 4–6px (uses [RadarDensity.tagRadius]).
class RadarTag extends StatelessWidget {
  const RadarTag({super.key, required this.label, this.severity, this.color});

  /// The text displayed inside the tag (shown as-is; caller supplies casing).
  final String label;

  /// Severity level used to derive background, border, and text colors.
  final RadarSeverity? severity;

  /// Explicit text and fill override; takes precedence over [severity].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? severity?.color ?? RadarColors.text40;
    final bg = _tagBg(effectiveColor);
    final border = _tagBorder(effectiveColor);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: RadarDensity.tagRadius,
        border: Border.all(color: border, width: RadarDensity.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RadarDensity.tagHPad,
          vertical: RadarDensity.tagVPad,
        ),
        child: Text(
          label,
          style: RadarTypography.monoTag.copyWith(color: effectiveColor),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }

  Color _tagBg(Color c) => Color.fromRGBO(
    // ignore: deprecated_member_use
    c.red,
    // ignore: deprecated_member_use
    c.green,
    // ignore: deprecated_member_use
    c.blue,
    0.12,
  );

  Color _tagBorder(Color c) => Color.fromRGBO(
    // ignore: deprecated_member_use
    c.red,
    // ignore: deprecated_member_use
    c.green,
    // ignore: deprecated_member_use
    c.blue,
    0.30,
  );
}
