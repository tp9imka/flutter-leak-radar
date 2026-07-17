import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_ui/src/widgets/radar_time_series_chart_painter.dart';

Set<String> _collectLabels(SemanticsNode node) {
  final labels = <String>{};
  void visit(SemanticsNode n) {
    final label = n.getSemanticsData().label;
    if (label.isNotEmpty) labels.add(label);
    n.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(node);
  return labels;
}

const _blue = Color(0xFF5ad1e6);
const _violet = Color(0xFFa78bfa);

List<({int tMicros, double value})> _line(List<double> values) => [
  for (var i = 0; i < values.length; i++)
    (tMicros: i * 1000000, value: values[i]),
];

Widget _host(Widget child, {double width = 722}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  group('RadarTimeSeriesChart widget', () {
    testWidgets('renders multi-series with a legend entry per series', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          RadarTimeSeriesChart(
            series: [
              ChartSeries(label: 'rss', color: _blue, points: _line([1, 2, 3])),
              ChartSeries(
                label: 'native',
                color: _violet,
                points: _line([4, 5, 6]),
              ),
            ],
          ),
        ),
      );

      expect(find.byType(RadarTimeSeriesChart), findsOneWidget);
      expect(find.text('rss'), findsOneWidget);
      expect(find.text('native'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty series list shows a placeholder and no legend', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const RadarTimeSeriesChart(series: [])));

      expect(find.text('no data'), findsOneWidget);
      expect(find.byType(Wrap), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('series with no points shows placeholder but keeps legend', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const RadarTimeSeriesChart(
            series: [ChartSeries(label: 'rss', color: _blue, points: [])],
          ),
        ),
      );

      expect(find.text('no data'), findsOneWidget);
      expect(find.text('rss'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('single-point series does not throw', (tester) async {
      await tester.pumpWidget(
        _host(
          RadarTimeSeriesChart(
            series: [
              ChartSeries(label: 's', color: _blue, points: _line([42])),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 722.0, 1280.0]) {
      testWidgets('no overflow at width $width', (tester) async {
        await tester.pumpWidget(
          _host(
            width: width,
            RadarTimeSeriesChart(
              yUnit: 'MB',
              threshold: 5,
              marks: const [
                ChartMark(tMicros: 1000000, label: 'route push happened'),
                ChartMark(tMicros: 4000000, label: 'gc'),
              ],
              shaded: const [ChartWindow(startMicros: 0, endMicros: 1500000)],
              series: [
                ChartSeries(
                  label: 'a very long resident-set-size series label',
                  color: _blue,
                  points: _line([1, 2, 3, 4, 5, 6]),
                  gaps: const [(startMicros: 2200000, endMicros: 2800000)],
                ),
                ChartSeries(
                  label: 'another comparably verbose native-heap label',
                  color: _violet,
                  points: _line([2, 3, 4, 5, 6, 7]),
                ),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('mark labels are exposed via painter semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          RadarTimeSeriesChart(
            marks: const [ChartMark(tMicros: 1000000, label: 'checkpoint')],
            series: [
              ChartSeries(label: 's', color: _blue, points: _line([1, 2, 3])),
            ],
          ),
        ),
      );

      final node = tester.getSemantics(
        find.descendant(
          of: find.byType(RadarTimeSeriesChart),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(_collectLabels(node), contains('checkpoint'));
      handle.dispose();
    });
  });

  group('segmentSeriesPoints (gap breaks)', () {
    test('no gaps yields a single run', () {
      final runs = segmentSeriesPoints(_line([1, 2, 3, 4]), const []);
      expect(runs, hasLength(1));
      expect(runs.first, hasLength(4));
    });

    test('a gap between two samples breaks into two runs', () {
      final runs = segmentSeriesPoints(_line([1, 2, 3, 4]), const [
        (startMicros: 1200000, endMicros: 1800000),
      ]);
      expect(runs, hasLength(2));
      // The break falls between the samples straddling the gap; no run holds
      // both, so the line is never drawn across it.
      expect(runs[0].last.tMicros, 1000000);
      expect(runs[1].first.tMicros, 2000000);
    });

    test('two gaps yield three runs', () {
      final runs = segmentSeriesPoints(_line([1, 2, 3, 4, 5]), const [
        (startMicros: 1200000, endMicros: 1800000),
        (startMicros: 2200000, endMicros: 2800000),
      ]);
      expect(runs, hasLength(3));
    });

    test('a gap outside the sampled range leaves one run', () {
      final runs = segmentSeriesPoints(_line([1, 2, 3]), const [
        (startMicros: 9000000, endMicros: 9500000),
      ]);
      expect(runs, hasLength(1));
    });

    test('unsorted samples are ordered before segmenting', () {
      final runs = segmentSeriesPoints([
        (tMicros: 3000000, value: 3),
        (tMicros: 1000000, value: 1),
        (tMicros: 2000000, value: 2),
      ], const []);
      expect(runs, hasLength(1));
      expect(runs.first.map((p) => p.tMicros), [1000000, 2000000, 3000000]);
    });

    test('a zero-width gap is an intentional no-op (no break)', () {
      // A gap whose start == end covers no time; it must never split the line
      // even when it lands exactly between two samples.
      final runs = segmentSeriesPoints(_line([1, 2, 3, 4]), const [
        (startMicros: 1500000, endMicros: 1500000),
      ]);
      expect(runs, hasLength(1));
      expect(runs.first, hasLength(4));
    });

    test('a sample on a gap boundary belongs to the adjacent run', () {
      // Sample at t=1_000_000 sits exactly on the gap start; strict
      // inequalities keep it out of the gap, so the break falls after it.
      final runs = segmentSeriesPoints(_line([1, 2, 3]), const [
        (startMicros: 1000000, endMicros: 1800000),
      ]);
      expect(runs, hasLength(2));
      expect(runs[0].last.tMicros, 1000000);
      expect(runs[1].first.tMicros, 2000000);
    });
  });

  group('buildTimeSeriesChartPlan', () {
    const size = Size(400, 240);

    TimeSeriesChartPlan planFor(
      List<ChartSeries> series, {
      List<ChartMark> marks = const [],
      List<ChartWindow> shaded = const [],
      double? threshold,
      String? yUnit,
      bool normalize = false,
    }) => buildTimeSeriesChartPlan(
      series: series,
      marks: marks,
      shaded: shaded,
      threshold: threshold,
      yUnit: yUnit,
      normalizePerSeries: normalize,
      size: size,
    );

    test('a gap produces two polylines and never bridges', () {
      final plan = planFor([
        ChartSeries(
          label: 's',
          color: _blue,
          points: _line([1, 2, 3, 4]),
          gaps: const [(startMicros: 1200000, endMicros: 1800000)],
        ),
      ]);
      final poly = plan.series.single.polylines;
      expect(poly, hasLength(2));
      // No single polyline spans the whole time domain: the max x of the
      // first run is strictly left of the min x of the second run.
      final firstRunMaxX = poly[0]
          .map((o) => o.dx)
          .reduce((a, b) => a > b ? a : b);
      final secondRunMinX = poly[1]
          .map((o) => o.dx)
          .reduce((a, b) => a < b ? a : b);
      expect(firstRunMaxX, lessThan(secondRunMinX));
      // Every sample is still plotted as a marker.
      expect(plan.series.single.markers, hasLength(4));
    });

    test('normalize scales each series independently', () {
      final small = ChartSeries(
        label: 'small',
        color: _blue,
        points: _line([0, 5, 10]),
      );
      final big = ChartSeries(
        label: 'big',
        color: _violet,
        points: _line([0, 500, 1000]),
      );

      double topmost(TimeSeriesSeriesPlan s) =>
          s.markers.map((o) => o.dy).reduce((a, b) => a < b ? a : b);

      final shared = planFor([small, big]);
      final normalized = planFor([small, big], normalize: true);

      // Normalized: BOTH series reach the top of the plot at their own max.
      expect(topmost(normalized.series[0]), closeTo(normalized.plot.top, 0.5));
      expect(topmost(normalized.series[1]), closeTo(normalized.plot.top, 0.5));

      // Shared: only the large series reaches the top; the small one stays
      // in the lower half because it is dwarfed by the shared max.
      expect(topmost(shared.series[1]), closeTo(shared.plot.top, 0.5));
      expect(
        topmost(shared.series[0]),
        greaterThan(shared.plot.top + shared.plot.height * 0.5),
      );
    });

    test('normalize with a single-point series is centered and finite', () {
      final plan = planFor([
        ChartSeries(label: 's', color: _blue, points: _line([42])),
      ], normalize: true);
      final marker = plan.series.single.markers.single;
      // A lone sample has no range, so it maps to the plot's vertical center
      // (never NaN from a divide-by-zero range).
      expect(marker.dy.isFinite, isTrue);
      expect(marker.dy, closeTo(plan.plot.center.dy, 0.5));
    });

    test('normalize with a constant-value series maps all to center', () {
      final plan = planFor([
        ChartSeries(label: 's', color: _blue, points: _line([7, 7, 7, 7])),
      ], normalize: true);
      final markers = plan.series.single.markers;
      expect(markers, hasLength(4));
      for (final m in markers) {
        expect(m.dy.isFinite, isTrue);
        expect(m.dy, closeTo(plan.plot.center.dy, 0.5));
      }
    });

    test('threshold line is placed when shared, omitted when normalized', () {
      final series = [
        ChartSeries(label: 's', color: _blue, points: _line([0, 10])),
      ];
      final shared = planFor(series, threshold: 5);
      expect(shared.thresholdY, isNotNull);
      expect(
        shared.thresholdY,
        inInclusiveRange(shared.plot.top, shared.plot.bottom),
      );

      final normalized = planFor(series, threshold: 5, normalize: true);
      expect(normalized.thresholdY, isNull);
    });

    test('marks and time ticks stay within the plot horizontally', () {
      final plan = planFor(
        [
          ChartSeries(label: 's', color: _blue, points: _line([1, 2, 3, 4])),
        ],
        marks: const [ChartMark(tMicros: 2000000, label: 'gc')],
      );
      for (final m in plan.marks) {
        expect(m.x, inInclusiveRange(plan.plot.left, plan.plot.right));
      }
      expect(plan.timeTicks, isNotEmpty);
      for (final t in plan.timeTicks) {
        expect(
          t.x,
          inInclusiveRange(plan.plot.left - 0.01, plan.plot.right + 0.01),
        );
      }
    });

    test('adaptive time-axis unit switches from seconds to minutes', () {
      final seconds = planFor([
        ChartSeries(label: 's', color: _blue, points: _line([1, 2, 3])),
      ]);
      expect(seconds.timeTicks.every((t) => t.label.endsWith('s')), isTrue);

      final longSpan = buildTimeSeriesChartPlan(
        series: [
          ChartSeries(
            label: 's',
            color: _blue,
            points: [(tMicros: 0, value: 1), (tMicros: 600000000, value: 2)],
          ),
        ],
        marks: const [],
        shaded: const [],
        threshold: null,
        yUnit: null,
        normalizePerSeries: false,
        size: size,
      );
      expect(longSpan.timeTicks.every((t) => t.label.endsWith('m')), isTrue);
    });

    test('shaded windows are clamped to the plot rect', () {
      final plan = planFor(
        [
          ChartSeries(label: 's', color: _blue, points: _line([1, 2, 3])),
        ],
        shaded: const [
          ChartWindow(startMicros: -5000000, endMicros: 999000000),
        ],
      );
      final w = plan.windows.single;
      expect(w.left, greaterThanOrEqualTo(plan.plot.left - 0.01));
      expect(w.right, lessThanOrEqualTo(plan.plot.right + 0.01));
    });

    test('empty input yields an empty plan without throwing', () {
      final plan = planFor(const []);
      expect(plan.series, isEmpty);
      expect(plan.timeTicks, isEmpty);
      expect(plan.marks, isEmpty);
    });

    test('value-axis labels carry the yUnit suffix', () {
      final plan = planFor([
        ChartSeries(label: 's', color: _blue, points: _line([0, 50, 100])),
      ], yUnit: 'MB');
      expect(plan.valueTicks, isNotEmpty);
      expect(plan.valueTicks.every((t) => t.label.endsWith('MB')), isTrue);
    });
  });
}
