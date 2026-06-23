import 'package:flutter/material.dart';

/// Tiny inline sparkline showing the live-count series from [LeakFinding.series].
///
/// Normalized to fit [height]; points are connected with a stroked line.
/// Handles empty and single-point series gracefully (renders nothing / a dot).
class GrowthSparkline extends StatelessWidget {
  const GrowthSparkline({
    super.key,
    required this.series,
    this.width = 80.0,
    this.height = 24.0,
    this.color = Colors.red,
    this.strokeWidth = 1.5,
  });

  final List<int> series;
  final double width;
  final double height;
  final Color color;
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
      // Single point: draw a dot.
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

    final path = Path();
    path.moveTo(0, toOffset(0, series.first).dy);
    for (var i = 0; i < series.length; i++) {
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
