import 'package:flutter/rendering.dart';
import 'package:radar_ui/radar_ui.dart';

/// Dims the whole overlay and, when [cutout] is a non-empty rect, cuts an
/// undimmed rounded hole around it with a soft accent ring — the
/// first-run guide's spotlight effect.
///
/// [cutout] is already in the overlay's own coordinate space (see
/// `_FirstRunGuideState._measure` in `first_run_guide.dart`). A null or
/// zero-size rect (anchor not yet measured, or a welcome/finish step
/// that has no anchor) simply paints the full dim backdrop with no
/// ring — this painter never throws on missing geometry.
class GuideSpotlightPainter extends CustomPainter {
  const GuideSpotlightPainter({
    required this.cutout,
    this.ringColor = RadarColors.accent,
    this.glowStrength = 0.5,
    this.reduceMotion = false,
  });

  /// The rect to leave undimmed and ring, in the painter's own
  /// coordinate space. Null or empty paints the dim layer only.
  final Rect? cutout;

  /// Ring + glow color — the design spec's accent.
  final Color ringColor;

  /// 0..1 driver for the glow's pulse; ignored (a fixed mid value reads
  /// best) when [reduceMotion] is true.
  final double glowStrength;

  /// Reduced-motion mode: the glow renders at a fixed strength instead
  /// of pulsing (the caller is responsible for not animating at all).
  final bool reduceMotion;

  /// Spec §7: dim backdrop `rgba(4, 6, 7, 0.72–0.78)` — not part of
  /// `RadarColors` since it's a one-off overlay scrim, not a surface.
  static const Color dimBackdrop = Color.fromRGBO(4, 6, 7, 0.75);

  static const double _cutoutRadius = 10;
  static const double _cutoutPadding = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final rect = cutout;
    final hasCutout = rect != null && rect.width > 0 && rect.height > 0;

    final dimPath = Path()..addRect(screen);
    RRect? ring;
    if (hasCutout) {
      ring = RRect.fromRectAndRadius(
        rect.inflate(_cutoutPadding),
        const Radius.circular(_cutoutRadius),
      );
      dimPath
        ..addRRect(ring)
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(dimPath, Paint()..color = dimBackdrop);

    if (ring == null) return;
    final glowOpacity = reduceMotion ? 0.35 : 0.3 + 0.35 * glowStrength;
    canvas.drawRRect(
      ring,
      Paint()
        ..color = ringColor.withValues(alpha: glowOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant GuideSpotlightPainter oldDelegate) =>
      cutout != oldDelegate.cutout ||
      ringColor != oldDelegate.ringColor ||
      glowStrength != oldDelegate.glowStrength ||
      reduceMotion != oldDelegate.reduceMotion;
}
