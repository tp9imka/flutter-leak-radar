// lib/src/widgets/radar_time_series_chart_painter.dart

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import '../tokens/typography.dart';
import 'radar_time_series_chart.dart';

/// Top inset above the plot area, in logical pixels.
const double kTimeSeriesTopPad = 10;

/// Right inset of the plot area, in logical pixels.
const double kTimeSeriesRightPad = 12;

/// Height reserved at the bottom for the time-axis tick labels.
const double kTimeSeriesBottomAxis = 20;

/// Width reserved at the left for the value-axis tick labels.
const double kTimeSeriesLeftGutter = 48;

/// A contiguous run of samples plus every sample's plotted marker, for one
/// [ChartSeries], resolved to pixel space.
///
/// [polylines] holds one entry per contiguous run of samples. A run boundary
/// is a measurement gap: the line is broken there and NEVER bridged, because
/// a gap means "not measured" and drawing across it would fabricate data.
@visibleForTesting
final class TimeSeriesSeriesPlan {
  const TimeSeriesSeriesPlan({
    required this.label,
    required this.color,
    required this.polylines,
    required this.markers,
  });

  /// The series label (mirrors [ChartSeries.label]).
  final String label;

  /// The series color (mirrors [ChartSeries.color]).
  final Color color;

  /// One polyline per contiguous (gap-free) run of samples.
  final List<List<Offset>> polylines;

  /// Every sample as a plotted marker point.
  final List<Offset> markers;
}

/// A fully resolved, pixel-space rendering plan for a [RadarTimeSeriesChart].
///
/// Pure output of [buildTimeSeriesChartPlan]; the painter only draws it and
/// tests assert against it (gap break counts, per-series normalization,
/// mark positions, in-bounds coordinates) without goldens.
@visibleForTesting
final class TimeSeriesChartPlan {
  const TimeSeriesChartPlan({
    required this.plot,
    required this.series,
    required this.marks,
    required this.windows,
    required this.thresholdY,
    required this.timeTicks,
    required this.valueTicks,
  });

  /// The plot rectangle (inside the axis gutters).
  final Rect plot;

  /// Per-series resolved geometry.
  final List<TimeSeriesSeriesPlan> series;

  /// Vertical checkpoint marks: x position and label.
  final List<({double x, String label})> marks;

  /// Shaded (settle) window rectangles, clamped to [plot].
  final List<Rect> windows;

  /// The horizontal threshold-line y, or null when absent / normalized.
  final double? thresholdY;

  /// Time-axis ticks: x position and adaptive (s/m/h) label.
  final List<({double x, String label})> timeTicks;

  /// Value-axis ticks: y position and label.
  final List<({double y, String label})> valueTicks;
}

/// Splits [points] into contiguous runs, breaking between two consecutive
/// samples whenever a gap in [gaps] overlaps the interval between them.
///
/// Samples need not be pre-sorted; a time-ordered copy is used. The returned
/// runs are exactly the segments the chart connects with a line — a gap is a
/// break, never a bridge. Returns an empty list for no samples.
@visibleForTesting
List<List<({int tMicros, double value})>> segmentSeriesPoints(
  List<({int tMicros, double value})> points,
  List<({int startMicros, int endMicros})> gaps,
) {
  if (points.isEmpty) return const [];
  final sorted = [...points]..sort((a, b) => a.tMicros.compareTo(b.tMicros));
  final runs = <List<({int tMicros, double value})>>[];
  var current = <({int tMicros, double value})>[sorted.first];
  for (var i = 1; i < sorted.length; i++) {
    final prev = sorted[i - 1];
    final cur = sorted[i];
    final broken = gaps.any(
      (g) => g.startMicros < cur.tMicros && g.endMicros > prev.tMicros,
    );
    if (broken) {
      runs.add(current);
      current = [cur];
    } else {
      current.add(cur);
    }
  }
  runs.add(current);
  return runs;
}

/// Builds the pixel-space [TimeSeriesChartPlan] for the given chart inputs at
/// [size]. Pure and side-effect-free — the single source of truth shared by
/// the painter and the widget tests.
@visibleForTesting
TimeSeriesChartPlan buildTimeSeriesChartPlan({
  required List<ChartSeries> series,
  required List<ChartMark> marks,
  required List<ChartWindow> shaded,
  required double? threshold,
  required String? yUnit,
  required bool normalizePerSeries,
  required Size size,
}) {
  final left = kTimeSeriesLeftGutter;
  final top = kTimeSeriesTopPad;
  final right = size.width - kTimeSeriesRightPad;
  final bottom = size.height - kTimeSeriesBottomAxis;
  final plot = Rect.fromLTRB(
    left,
    top,
    math.max(left, right),
    math.max(top, bottom),
  );
  final plotW = right - left;
  final plotH = bottom - top;

  if (plotW <= 0 || plotH <= 0) {
    return TimeSeriesChartPlan(
      plot: plot,
      series: const [],
      marks: const [],
      windows: const [],
      thresholdY: null,
      timeTicks: const [],
      valueTicks: const [],
    );
  }

  final domain = _timeDomain(series, marks, shaded);
  if (domain == null) {
    return TimeSeriesChartPlan(
      plot: plot,
      series: const [],
      marks: const [],
      windows: const [],
      thresholdY: null,
      timeTicks: const [],
      valueTicks: const [],
    );
  }
  final (tMin, tMax) = domain;
  double xOf(int t) => tMax == tMin
      ? left + plotW / 2
      : left + plotW * (t - tMin) / (tMax - tMin);

  // Shared value domain (only meaningful when not normalizing per series).
  var gMin = double.infinity;
  var gMax = double.negativeInfinity;
  for (final s in series) {
    for (final p in s.points) {
      gMin = math.min(gMin, p.value);
      gMax = math.max(gMax, p.value);
    }
  }
  if (!normalizePerSeries && threshold != null) {
    gMin = math.min(gMin, threshold);
    gMax = math.max(gMax, threshold);
  }

  double Function(double) yMapper(double lo, double hi) {
    final range = hi - lo;
    return (v) =>
        range == 0 ? top + plotH / 2 : bottom - plotH * (v - lo) / range;
  }

  final sharedY = yMapper(gMin, gMax);

  final seriesPlans = <TimeSeriesSeriesPlan>[];
  for (final s in series) {
    double Function(double) yOf;
    if (normalizePerSeries) {
      var lo = double.infinity;
      var hi = double.negativeInfinity;
      for (final p in s.points) {
        lo = math.min(lo, p.value);
        hi = math.max(hi, p.value);
      }
      yOf = s.points.isEmpty ? sharedY : yMapper(lo, hi);
    } else {
      yOf = sharedY;
    }
    final runs = segmentSeriesPoints(s.points, s.gaps);
    final polylines = <List<Offset>>[
      for (final run in runs)
        [for (final p in run) Offset(xOf(p.tMicros), yOf(p.value))],
    ];
    final markers = <Offset>[
      for (final run in runs)
        for (final p in run) Offset(xOf(p.tMicros), yOf(p.value)),
    ];
    seriesPlans.add(
      TimeSeriesSeriesPlan(
        label: s.label,
        color: s.color,
        polylines: polylines,
        markers: markers,
      ),
    );
  }

  final markPlans = <({double x, String label})>[
    for (final m in marks) (x: xOf(m.tMicros), label: m.label),
  ];

  final windowRects = <Rect>[
    for (final w in shaded)
      Rect.fromLTRB(
        xOf(w.startMicros).clamp(left, right),
        top,
        xOf(w.endMicros).clamp(left, right),
        bottom,
      ),
  ];

  final double? thresholdY = (normalizePerSeries || threshold == null)
      ? null
      : sharedY(threshold);

  final timeTicks = _timeTicks(tMin, tMax, xOf);
  final valueTicks = normalizePerSeries
      ? <({double y, String label})>[
          (y: top, label: '1'),
          (y: top + plotH / 2, label: '.5'),
          (y: bottom, label: '0'),
        ]
      : _valueTicks(gMin, gMax, sharedY, top, bottom, yUnit);

  return TimeSeriesChartPlan(
    plot: plot,
    series: seriesPlans,
    marks: markPlans,
    windows: windowRects,
    thresholdY: thresholdY,
    timeTicks: timeTicks,
    valueTicks: valueTicks,
  );
}

(int, int)? _timeDomain(
  List<ChartSeries> series,
  List<ChartMark> marks,
  List<ChartWindow> shaded,
) {
  int? lo;
  int? hi;
  void acc(int v) {
    lo = lo == null ? v : math.min(lo!, v);
    hi = hi == null ? v : math.max(hi!, v);
  }

  for (final s in series) {
    for (final p in s.points) {
      acc(p.tMicros);
    }
  }
  for (final m in marks) {
    acc(m.tMicros);
  }
  for (final w in shaded) {
    acc(w.startMicros);
    acc(w.endMicros);
  }
  if (lo == null) return null;
  return (lo!, hi!);
}

({double base, String suffix}) _pickTimeAxis(int spanMicros) {
  final seconds = spanMicros / 1e6;
  if (seconds <= 90) return (base: 1e6, suffix: 's');
  if (seconds <= 90 * 60) return (base: 60e6, suffix: 'm');
  return (base: 3600e6, suffix: 'h');
}

double _niceStep(double rough) {
  if (rough <= 0 || !rough.isFinite) return 1;
  final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final norm = rough / mag;
  final nice = norm < 1.5
      ? 1.0
      : norm < 3
      ? 2.0
      : norm < 7
      ? 5.0
      : 10.0;
  return nice * mag;
}

String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

List<({double x, String label})> _timeTicks(
  int tMin,
  int tMax,
  double Function(int) xOf,
) {
  final axis = _pickTimeAxis(tMax - tMin);
  final spanUnits = (tMax - tMin) / axis.base;
  if (spanUnits <= 0) {
    return [(x: xOf(tMin), label: '0${axis.suffix}')];
  }
  final step = _niceStep(spanUnits / 4);
  final ticks = <({double x, String label})>[];
  for (var u = 0.0; u <= spanUnits + 1e-9; u += step) {
    final t = tMin + (u * axis.base).round();
    ticks.add((x: xOf(t), label: '${_fmtNum(u)}${axis.suffix}'));
    if (ticks.length >= 12) break;
  }
  return ticks;
}

List<({double y, String label})> _valueTicks(
  double gMin,
  double gMax,
  double Function(double) yOf,
  double top,
  double bottom,
  String? yUnit,
) {
  final unit = yUnit == null ? '' : ' $yUnit';
  if (!gMin.isFinite || !gMax.isFinite) return const [];
  if (gMax == gMin) {
    return [(y: yOf(gMin), label: '${_fmtNum(gMin)}$unit')];
  }
  final step = _niceStep((gMax - gMin) / 3);
  final ticks = <({double y, String label})>[];
  final start = (gMin / step).floor() * step;
  for (var v = start; v <= gMax + step * 1e-9; v += step) {
    if (v < gMin - step * 1e-9) continue;
    final y = yOf(v);
    if (y < top - 0.5 || y > bottom + 0.5) continue;
    ticks.add((y: y, label: '${_fmtNum(v)}$unit'));
    if (ticks.length >= 8) break;
  }
  return ticks;
}

/// Paints a [RadarTimeSeriesChart] from a [buildTimeSeriesChartPlan] plan.
///
/// Draws, back to front: shaded windows, value gridlines, the threshold line,
/// each series' broken polylines and markers, checkpoint marks, and the axis
/// tick labels. Exposes mark labels through [semanticsBuilder].
class TimeSeriesChartPainter extends CustomPainter {
  const TimeSeriesChartPainter({
    required this.series,
    required this.marks,
    required this.shaded,
    required this.threshold,
    required this.yUnit,
    required this.normalizePerSeries,
  });

  /// The series to plot.
  final List<ChartSeries> series;

  /// Vertical checkpoint marks.
  final List<ChartMark> marks;

  /// Shaded (settle) windows drawn behind the series.
  final List<ChartWindow> shaded;

  /// Optional horizontal threshold line (ignored when normalizing).
  final double? threshold;

  /// Optional unit suffix for value-axis labels.
  final String? yUnit;

  /// When true, each series is scaled to its own min/max independently.
  final bool normalizePerSeries;

  TimeSeriesChartPlan _plan(Size size) => buildTimeSeriesChartPlan(
    series: series,
    marks: marks,
    shaded: shaded,
    threshold: threshold,
    yUnit: yUnit,
    normalizePerSeries: normalizePerSeries,
    size: size,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final plan = _plan(size);
    final plot = plan.plot;
    if (plot.width <= 0 || plot.height <= 0) return;

    // Shaded settle windows (behind everything).
    final windowFill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color.fromRGBO(90, 209, 230, 0.06);
    final windowEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color.fromRGBO(90, 209, 230, 0.18);
    for (final w in plan.windows) {
      canvas.drawRect(w, windowFill);
      canvas.drawLine(w.topLeft, w.bottomLeft, windowEdge);
      canvas.drawLine(w.topRight, w.bottomRight, windowEdge);
    }

    // Value gridlines.
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = RadarColors.hairline05;
    for (final t in plan.valueTicks) {
      canvas.drawLine(
        Offset(plot.left, t.y),
        Offset(plot.right, t.y),
        gridPaint,
      );
    }

    // Threshold line (dashed).
    final thresholdY = plan.thresholdY;
    if (thresholdY != null) {
      _dashedLine(
        canvas,
        Offset(plot.left, thresholdY),
        Offset(plot.right, thresholdY),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = RadarColors.warning.withValues(alpha: 0.75),
      );
    }

    // Series lines + markers, clipped to the plot.
    canvas.save();
    canvas.clipRect(plot);
    for (final s in plan.series) {
      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = s.color;
      for (final poly in s.polylines) {
        if (poly.length < 2) continue;
        final path = Path()..moveTo(poly.first.dx, poly.first.dy);
        for (var i = 1; i < poly.length; i++) {
          path.lineTo(poly[i].dx, poly[i].dy);
        }
        canvas.drawPath(path, linePaint);
      }
      final markerPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = s.color;
      for (final m in s.markers) {
        canvas.drawCircle(m, 2.0, markerPaint);
      }
    }
    canvas.restore();

    // Checkpoint marks (vertical dashed line + label).
    final markPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = RadarColors.text25;
    for (final m in plan.marks) {
      _dashedLine(
        canvas,
        Offset(m.x, plot.top),
        Offset(m.x, plot.bottom),
        markPaint,
      );
      _paintMarkLabel(canvas, m.label, m.x, plot);
    }

    // Value-axis tick labels (left gutter, right-aligned to the plot edge).
    for (final t in plan.valueTicks) {
      _paintText(
        canvas,
        t.label,
        right: plot.left - 6,
        centerY: t.y,
        maxWidth: kTimeSeriesLeftGutter - 8,
      );
    }

    // Time-axis tick labels (bottom band, centered on the tick).
    for (final t in plan.timeTicks) {
      _paintText(
        canvas,
        t.label,
        centerX: t.x,
        top: plot.bottom + 4,
        clampLeft: plot.left,
        clampRight: plot.right,
      );
    }
  }

  void _paintMarkLabel(Canvas canvas, String label, double x, Rect plot) {
    final tp = _layout(label, maxWidth: 90);
    // Anchor to the right of the line, flipping left near the plot edge.
    final fitsRight = x + 3 + tp.width <= plot.right;
    final dx = fitsRight ? x + 3 : x - 3 - tp.width;
    tp.paint(
      canvas,
      Offset(dx.clamp(plot.left, plot.right - tp.width), plot.top + 1),
    );
  }

  void _paintText(
    Canvas canvas,
    String label, {
    double? centerX,
    double? centerY,
    double? right,
    double? top,
    double clampLeft = 0,
    double clampRight = double.infinity,
    double maxWidth = 120,
  }) {
    final tp = _layout(label, maxWidth: maxWidth);
    var dx = 0.0;
    if (centerX != null) {
      dx = centerX - tp.width / 2;
    } else if (right != null) {
      dx = right - tp.width;
    }
    dx = dx.clamp(clampLeft, math.max(clampLeft, clampRight - tp.width));
    final dy = centerY != null ? centerY - tp.height / 2 : (top ?? 0);
    tp.paint(canvas, Offset(dx, dy));
  }

  TextPainter _layout(String label, {required double maxWidth}) => TextPainter(
    text: TextSpan(text: label, style: RadarTypography.monoLabel),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 3.0;
    const gap = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final start = a + dir * drawn;
      final end = a + dir * math.min(drawn + dash, total);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  SemanticsBuilderCallback? get semanticsBuilder => (size) {
    final plan = _plan(size);
    return [
      for (final m in plan.marks)
        CustomPainterSemantics(
          rect: Rect.fromLTWH(
            (m.x - 6).clamp(0.0, size.width),
            plan.plot.top,
            12,
            plan.plot.height,
          ),
          properties: SemanticsProperties(
            label: m.label,
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };

  @override
  bool shouldRepaint(TimeSeriesChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.marks != marks ||
      oldDelegate.shaded != shaded ||
      oldDelegate.threshold != threshold ||
      oldDelegate.yUnit != yUnit ||
      oldDelegate.normalizePerSeries != normalizePerSeries;

  @override
  bool shouldRebuildSemantics(TimeSeriesChartPainter oldDelegate) =>
      oldDelegate.marks != marks;
}
