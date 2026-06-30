// packages/flutter_perf_radar/test/frames_tab_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_trace/radar_trace.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds a [FrameStatsSnapshot] with [n] identical frames.
FrameStatsSnapshot _buildSnapshot({
  int frameCount = 0,
  int jankCount = 0,
  List<FrameSample> recentFrames = const [],
}) {
  return FrameStatsSnapshot(
    frameCount: frameCount,
    jankCount: jankCount,
    recentFrames: recentFrames,
  );
}

FrameSample _sample({
  int totalMicros = 8000,
  int buildMicros = 5000,
  int rasterMicros = 3000,
}) => FrameSample(
  totalMicros: totalMicros,
  buildMicros: buildMicros,
  rasterMicros: rasterMicros,
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// ── FrameTimeline via FramesTab ───────────────────────────────────────────────

void main() {
  group('FramesTab — empty state', () {
    testWidgets('shows placeholder when recentFrames is empty', (tester) async {
      await tester.pumpWidget(_wrap(FramesTab(stats: _buildSnapshot())));
      expect(find.text('No frames recorded yet.'), findsOneWidget);
    });

    testWidgets('does NOT show worst-frames section when empty', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(FramesTab(stats: _buildSnapshot())));
      expect(find.text('WORST RECENT FRAMES'), findsNothing);
    });
  });

  group('FramesTab — real frame data', () {
    testWidgets('renders without error when recentFrames has entries', (
      tester,
    ) async {
      final frames = List.generate(
        10,
        (i) => _sample(totalMicros: (i + 1) * 2000),
      );
      await tester.pumpWidget(
        _wrap(
          FramesTab(
            stats: _buildSnapshot(
              frameCount: frames.length,
              recentFrames: frames,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('does NOT show placeholder when frames are present', (
      tester,
    ) async {
      final frames = [_sample(totalMicros: 8000)];
      await tester.pumpWidget(
        _wrap(
          FramesTab(stats: _buildSnapshot(frameCount: 1, recentFrames: frames)),
        ),
      );
      expect(find.text('No frames recorded yet.'), findsNothing);
    });

    testWidgets('shows WORST RECENT FRAMES section when frames are present', (
      tester,
    ) async {
      final frames = [_sample(totalMicros: 8000)];
      await tester.pumpWidget(
        _wrap(
          FramesTab(stats: _buildSnapshot(frameCount: 1, recentFrames: frames)),
        ),
      );
      expect(find.text('WORST RECENT FRAMES'), findsOneWidget);
    });
  });

  group('FramesTab — worst frames from ring', () {
    testWidgets('worst frame shows BUILD-BOUND when build > raster', (
      tester,
    ) async {
      final frames = [
        _sample(totalMicros: 20000, buildMicros: 15000, rasterMicros: 5000),
      ];
      await tester.pumpWidget(
        _wrap(
          FramesTab(
            stats: _buildSnapshot(
              frameCount: 1,
              jankCount: 1,
              recentFrames: frames,
            ),
          ),
        ),
      );
      expect(find.text('BUILD-BOUND'), findsOneWidget);
      expect(find.text('RASTER-BOUND'), findsNothing);
    });

    testWidgets('worst frame shows RASTER-BOUND when raster > build', (
      tester,
    ) async {
      final frames = [
        _sample(totalMicros: 25000, buildMicros: 5000, rasterMicros: 20000),
      ];
      await tester.pumpWidget(
        _wrap(
          FramesTab(
            stats: _buildSnapshot(
              frameCount: 1,
              jankCount: 1,
              recentFrames: frames,
            ),
          ),
        ),
      );
      expect(find.text('RASTER-BOUND'), findsOneWidget);
      expect(find.text('BUILD-BOUND'), findsNothing);
    });

    testWidgets('shows at most 5 worst-frame rows for large ring', (
      tester,
    ) async {
      // 10 frames of varying durations
      final frames = List.generate(
        10,
        (i) => _sample(
          totalMicros: (i + 1) * 5000,
          buildMicros: (i + 1) * 3000,
          rasterMicros: (i + 1) * 2000,
        ),
      );
      await tester.pumpWidget(
        _wrap(
          FramesTab(
            stats: _buildSnapshot(
              frameCount: frames.length,
              recentFrames: frames,
            ),
          ),
        ),
      );
      // Both tags appear (build > raster for every sample above)
      final buildBound = find.text('BUILD-BOUND');
      final rasterBound = find.text('RASTER-BOUND');
      final total =
          tester.widgetList(buildBound).length +
          tester.widgetList(rasterBound).length;
      expect(total, lessThanOrEqualTo(5));
    });

    testWidgets('worst frames are sorted by totalMicros descending', (
      tester,
    ) async {
      // Build three frames: slow, medium, fast — worst should appear first.
      final slow = _sample(
        totalMicros: 50000,
        buildMicros: 40000,
        rasterMicros: 10000,
      );
      final medium = _sample(
        totalMicros: 20000,
        buildMicros: 15000,
        rasterMicros: 5000,
      );
      final fast = _sample(
        totalMicros: 5000,
        buildMicros: 3000,
        rasterMicros: 2000,
      );
      await tester.pumpWidget(
        _wrap(
          FramesTab(
            stats: _buildSnapshot(
              frameCount: 3,
              recentFrames: [fast, slow, medium],
            ),
          ),
        ),
      );
      // The 50ms value should appear (formatted as "50.0ms" by _pct)
      expect(find.textContaining('50.0ms'), findsOneWidget);
    });

    testWidgets(
      'no fabricated frame ids or cause labels in worst-frames list',
      (tester) async {
        final frames = [
          _sample(totalMicros: 20000, buildMicros: 12000, rasterMicros: 8000),
        ];
        await tester.pumpWidget(
          _wrap(
            FramesTab(
              stats: _buildSnapshot(frameCount: 1, recentFrames: frames),
            ),
          ),
        );
        // Verify no frame-id or cause labels appear
        expect(find.textContaining('frame #'), findsNothing);
        expect(find.textContaining('cause:'), findsNothing);
        expect(find.textContaining('p99 frame'), findsNothing);
        expect(find.textContaining('p95 frame'), findsNothing);
      },
    );
  });

  group('StartupTab — measured state (no fabricated phase split)', () {
    testWidgets('shows TTF headline but NO fabricated phase rows', (
      tester,
    ) async {
      final hist = LatencyHistogram()..record(300000); // 300ms startup
      const key = TraceKey(name: 'startup', category: 'perf_radar');
      final stats = SpanKeyStatsSnapshot(
        key: key,
        count: 1,
        errorCount: 0,
        histogram: hist.snapshot(),
        outliers: const [],
        firstStartMicros: 0,
        lastStartMicros: 0,
      );
      final snapshot = TraceSnapshot(stats: {key: stats}, totalDropCount: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StartupTab(snapshot: snapshot)),
        ),
      );

      expect(find.text('Time to first frame'), findsOneWidget);
      expect(find.textContaining('300ms'), findsOneWidget);

      // The fabricated phase labels must not appear
      expect(find.text('Engine init'), findsNothing);
      expect(find.text('Dart VM + isolate'), findsNothing);
      expect(find.text('First frame build'), findsNothing);
      expect(find.text('First frame raster'), findsNothing);
    });

    testWidgets('shows honest note card directing to PerfRadar.trace()', (
      tester,
    ) async {
      final hist = LatencyHistogram()..record(450000);
      const key = TraceKey(name: 'startup', category: 'perf_radar');
      final stats = SpanKeyStatsSnapshot(
        key: key,
        count: 1,
        errorCount: 0,
        histogram: hist.snapshot(),
        outliers: const [],
        firstStartMicros: 0,
        lastStartMicros: 0,
      );
      final snapshot = TraceSnapshot(stats: {key: stats}, totalDropCount: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StartupTab(snapshot: snapshot)),
        ),
      );

      expect(find.textContaining('PerfRadar.trace()'), findsOneWidget);
      expect(find.textContaining('not instrumented'), findsOneWidget);
    });
  });
}
