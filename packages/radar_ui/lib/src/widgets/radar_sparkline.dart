import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';

/// A miniature line chart for displaying a metric series inline.
///
/// Renders as a [CustomPaint] at [width]×[height]. The series is
/// normalized to fit the available height. Handles empty and
/// single-point series without errors.
///
/// Spec: 52×16px default, severity-colored stroke.
class RadarSparkline extends StatelessWidget {
  const RadarSparkline({
    super.key,
    required this.series,
    this.width = RadarDensity.sparklineWidth,
    this.height = RadarDensity.sparklineHeight,
    this.color = RadarColors.critical,
    this.strokeWidth = 1.5,
  });

  /// Data points to render (non-negative integers).
  final List<int> series;

  /// Width of the sparkline canvas.
  final double width;

  /// Height of the sparkline canvas.
  final double height;

  /// Stroke color; typically the severity color for this finding.
  final Color color;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          series: series,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.series,
    required this.color,
    required this.strokeWidth,
  });

  final List<int> series;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (series.length == 1) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        strokeWidth,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final maxVal = series.reduce((a, b) => a > b ? a : b);
    final minVal = series.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).toDouble();

    Offset toOffset(int i, int v) {
      final x = size.width * i / (series.length - 1);
      final y = range == 0
          ? size.height / 2
          : size.height * (1.0 - (v - minVal) / range);
      return Offset(x, y);
    }

    final path = Path()..moveTo(0, toOffset(0, series.first).dy);
    for (var i = 1; i < series.length; i++) {
      final o = toOffset(i, series[i]);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.series != series ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
