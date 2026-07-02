import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';

/// A full-size trend chart: a stroked line, a translucent filled area beneath
/// it, and a circular marker at each point. Used for plotting a class's
/// instance/byte count across N heap dumps over time (the soak-test view).
///
/// Modeled on [RadarSparkline]'s painter but sized for a panel, with inset
/// padding so end markers aren't clipped and a filled area under the line.
/// Renders nothing for an empty series; a flat line + single marker for one
/// point.
class RadarTrendChart extends StatelessWidget {
  const RadarTrendChart({
    super.key,
    required this.series,
    this.color = RadarColors.warning,
    this.strokeWidth = 2.0,
    this.height = 200.0,
  });

  /// Y values in point order (non-negative).
  final List<num> series;

  /// Line + marker color; area is drawn at 10% opacity of this.
  final Color color;

  final double strokeWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendPainter(
          series: series,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.series,
    required this.color,
    required this.strokeWidth,
  });

  final List<num> series;
  final Color color;
  final double strokeWidth;

  static const _inset = 6.0; // room for end markers
  static const _markerRadius = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;

    final left = _inset;
    final right = size.width - _inset;
    final top = _inset;
    final bottom = size.height - _inset;
    final plotW = (right - left).clamp(0.0, double.infinity);
    final plotH = (bottom - top).clamp(0.0, double.infinity);

    final maxVal = series.reduce((a, b) => a > b ? a : b);
    final minVal = series.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).toDouble();

    Offset toOffset(int i, num v) {
      final x = series.length == 1
          ? left + plotW / 2
          : left + plotW * i / (series.length - 1);
      final y = range == 0
          ? top + plotH / 2
          : top + plotH * (1.0 - (v - minVal) / range);
      return Offset(x, y);
    }

    final points = <Offset>[
      for (var i = 0; i < series.length; i++) toOffset(i, series[i]),
    ];

    // Filled area under the line.
    if (points.length > 1) {
      final area = Path()..moveTo(points.first.dx, bottom);
      for (final p in points) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(points.last.dx, bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.10),
      );
    }

    // The line.
    if (points.length > 1) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        line.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }

    // Markers.
    final markerPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    for (final p in points) {
      canvas.drawCircle(p, _markerRadius, markerPaint);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.series != series ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
