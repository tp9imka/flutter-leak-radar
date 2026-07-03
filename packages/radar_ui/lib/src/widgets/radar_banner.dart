// lib/src/widgets/radar_banner.dart

import 'package:flutter/widgets.dart';

import '../tokens/density.dart';
import '../tokens/severity.dart';
import '../tokens/typography.dart';

/// A full-width, severity-tinted notice banner.
///
/// Tint is derived from [severity] via [SeverityTokens.rowBg] /
/// [SeverityTokens.rowBorder]. The [message] is rendered in mono; an
/// optional [leading] widget (e.g., an icon) and trailing [action]
/// (e.g., a button) may be supplied.
class RadarBanner extends StatelessWidget {
  const RadarBanner({
    super.key,
    required this.message,
    this.severity = RadarSeverity.info,
    this.leading,
    this.action,
  });

  /// The notice text.
  final String message;

  /// Severity level; determines the banner's tint.
  final RadarSeverity severity;

  /// Optional widget shown before the message (e.g., an icon).
  final Widget? leading;

  /// Optional trailing widget (e.g., a button) shown after the message.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = severity.tokens;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.rowBg,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: tokens.rowBorder,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RadarDensity.rowHPad,
          vertical: RadarDensity.rowVPad,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Expanded(child: Text(message, style: RadarTypography.monoBody)),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        ),
      ),
    );
  }
}
