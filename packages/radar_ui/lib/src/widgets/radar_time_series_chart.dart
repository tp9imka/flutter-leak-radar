// lib/src/widgets/radar_time_series_chart.dart

import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import '../tokens/typography.dart';
import 'radar_time_series_chart_painter.dart';

/// One plotted line in a [RadarTimeSeriesChart].
///
/// [points] are time-value samples (need not be pre-sorted; they render in
/// time order). [gaps] are intervals with no measurement: a gap that falls
/// between two samples renders as a BREAK in the line and is never bridged,
/// because a gap means "not measured" and connecting across it would
/// fabricate data the sampler never observed.
final class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.points,
    this.gaps = const [],
  });

  /// The legend label for this series.
  final String label;

  /// The line and marker color for this series.
  final Color color;

  /// Time-value samples in microseconds / arbitrary value units.
  final List<({int tMicros, double value})> points;

  /// Unmeasured intervals, each rendered as a line break (never bridged).
  ///
  /// Boundary convention (half-open, strict inequalities): a gap breaks the
  /// line between two consecutive samples when
  /// `startMicros < laterSample.tMicros && endMicros > earlierSample.tMicros`.
  /// Because both comparisons are strict, a sample lying exactly on a gap
  /// boundary belongs to the adjacent run rather than being swallowed by the
  /// gap, and a zero-width gap (`startMicros == endMicros`) is an intentional
  /// no-op.
  final List<({int startMicros, int endMicros})> gaps;
}

/// A labeled vertical checkpoint drawn across the plot (e.g. a GC, a route
/// push, a native module load).
final class ChartMark {
  const ChartMark({required this.tMicros, required this.label});

  /// The checkpoint time in microseconds.
  final int tMicros;

  /// The checkpoint label, drawn beside the vertical line.
  final String label;
}

/// A shaded time window drawn behind the series (e.g. a settle window during
/// which growth is expected and not yet assessed).
final class ChartWindow {
  const ChartWindow({required this.startMicros, required this.endMicros});

  /// The window start time in microseconds.
  final int startMicros;

  /// The window end time in microseconds.
  final int endMicros;
}

/// A dark-only multi-series time chart for the Radar suite.
///
/// Plots one or more [ChartSeries] on a shared time axis with adaptive
/// (s/m/h) tick labels, a wrapping legend, checkpoint [marks], shaded
/// settle [shaded] windows, and an optional horizontal [threshold] line.
///
/// Honest rendering is the design requirement:
/// * A measurement gap ([ChartSeries.gaps]) is a line BREAK, never bridged.
/// * With [normalizePerSeries] each series is scaled to its own min/max so
///   multi-unit series can overlay; the [threshold] line is then omitted
///   because it has no single shared value to sit at.
///
/// Empty and single-point inputs are safe, and the widget never overflows
/// horizontally at any width of 320px or more (the legend wraps and each
/// entry ellipsizes).
///
/// This is a separate component from [RadarTrendChart], which is a
/// single-series Y-values-only sparkline painter.
///
/// Repaint is keyed on reference equality of the input lists — replace
/// [series]/[marks]/[shaded] with new lists rather than mutating them in
/// place, or the chart may not repaint.
class RadarTimeSeriesChart extends StatelessWidget {
  const RadarTimeSeriesChart({
    super.key,
    required this.series,
    this.marks = const [],
    this.shaded = const [],
    this.threshold,
    this.yUnit,
    this.normalizePerSeries = false,
    this.height = 240,
  }) : assert(
         threshold == null || !normalizePerSeries,
         'threshold is ignored when normalizePerSeries is true: a per-series '
         'normalized overlay has no shared value for the line to sit at.',
       );

  /// The series to plot. May be empty (renders a "no data" placeholder).
  final List<ChartSeries> series;

  /// Vertical checkpoint marks.
  final List<ChartMark> marks;

  /// Shaded (settle) windows drawn behind the series.
  final List<ChartWindow> shaded;

  /// Optional horizontal threshold line; ignored when [normalizePerSeries].
  final double? threshold;

  /// Optional unit suffix for value-axis labels (e.g. `'MB'`).
  final String? yUnit;

  /// When true, each series is scaled to its own min/max independently so
  /// series with different units can overlay meaningfully.
  final bool normalizePerSeries;

  /// The height of the plot area (excludes the legend below it).
  final double height;

  @override
  Widget build(BuildContext context) {
    final hasPoints = series.any((s) => s.points.isNotEmpty);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: hasPoints
                  ? CustomPaint(
                      painter: TimeSeriesChartPainter(
                        series: series,
                        marks: marks,
                        shaded: shaded,
                        threshold: threshold,
                        yUnit: yUnit,
                        normalizePerSeries: normalizePerSeries,
                      ),
                      child: const SizedBox.expand(),
                    )
                  : const _EmptyPlot(),
            ),
            if (series.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ChartLegend(series: series, available: available),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyPlot extends StatelessWidget {
  const _EmptyPlot();

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('no data', style: RadarTypography.monoLabel));
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.series, required this.available});

  final List<ChartSeries> series;
  final double available;

  @override
  Widget build(BuildContext context) {
    // Cap each entry's label so a single long label can never exceed the
    // available width; the Wrap moves overflow onto new lines instead.
    final maxLabelWidth = (available - 24).clamp(24.0, 220.0);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final s in series)
          _LegendEntry(
            label: s.label,
            color: s.color,
            maxLabelWidth: maxLabelWidth,
          ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.label,
    required this.color,
    required this.maxLabelWidth,
  });

  final String label;
  final Color color;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(Radius.circular(1.5)),
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxLabelWidth),
          child: Text(
            label,
            style: RadarTypography.monoLabel.copyWith(
              color: RadarColors.text60,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
