// lib/src/ui/theme/radar_glyph.dart

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'colors.dart';

/// Radar-scope decorative widget.
///
/// Draws concentric rings, a crosshair, and a static sweep wedge using
/// [LeakRadarColors.accent] at various opacities. Fully const-constructible.
class RadarGlyph extends StatelessWidget {
  const RadarGlyph({super.key, this.size = 64});

  /// Diameter of the bounding box (width == height).
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _RadarPainter()),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // ── Concentric rings ─────────────────────────────────────────────────────
    final ringOpacities = [0.08, 0.12, 0.18, 0.28];
    for (var i = 0; i < ringOpacities.length; i++) {
      final fraction = (i + 1) / ringOpacities.length;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..color = LeakRadarColors.accent.withValues(alpha: ringOpacities[i]);
      canvas.drawCircle(center, maxR * fraction, paint);
    }

    // ── Sweep wedge (static, like a frozen radar arm) ──────────────────────
    const sweepStart = -math.pi / 2; // 12 o'clock
    const sweepAngle = math.pi / 5; // ~36° arc
    final sweepPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          LeakRadarColors.accent.withValues(alpha: 0.18),
          LeakRadarColors.accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxR));

    final sweepPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: maxR),
        sweepStart,
        sweepAngle,
        false,
      )
      ..close();
    canvas.drawPath(sweepPath, sweepPaint);

    // ── Crosshair ─────────────────────────────────────────────────────────────
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = LeakRadarColors.accent.withValues(alpha: 0.22);

    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      crossPaint,
    );

    // ── Centre dot ────────────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      1.5,
      Paint()..color = LeakRadarColors.accent.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) => false;
}
