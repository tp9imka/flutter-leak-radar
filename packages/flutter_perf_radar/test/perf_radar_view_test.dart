// packages/flutter_perf_radar/test/perf_radar_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_trace/radar_trace.dart';

void main() {
  group('PerfRadarView', () {
    testWidgets('renders inside a Scaffold without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(children: [Expanded(child: PerfRadarView())]),
          ),
        ),
      );
      expect(find.byType(PerfRadarView), findsOneWidget);
    });

    // ── New sub-tab labels ──────────────────────────────────────────────────

    testWidgets('shows Traces sub-tab label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      expect(find.text('Traces'), findsOneWidget);
    });

    testWidgets('shows Frames sub-tab label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      expect(find.text('Frames'), findsOneWidget);
    });

    testWidgets('shows Rebuilds sub-tab label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      expect(find.text('Rebuilds'), findsOneWidget);
    });

    testWidgets('shows Startup sub-tab label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      expect(find.text('Startup'), findsOneWidget);
    });

    testWidgets('PerfRadarScreen still works after refactor', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PerfRadarScreen()));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Perf Radar'), findsOneWidget);
    });

    // ── Tab switching ──────────────────────────────────────────────────────

    testWidgets('tapping Frames sub-tab switches to frames body', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      await tester.tap(find.text('Frames'));
      await tester.pumpAndSettle();
      // Frames tab shows a jank-related tile
      expect(find.text('jank frames'), findsOneWidget);
    });

    testWidgets('tapping Rebuilds sub-tab switches to rebuilds body', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      await tester.tap(find.text('Rebuilds'));
      await tester.pumpAndSettle();
      // Empty rebuilds state
      expect(find.textContaining('TracedSubtree'), findsOneWidget);
    });

    testWidgets('tapping Startup sub-tab shows not-measured state', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      await tester.tap(find.text('Startup'));
      await tester.pumpAndSettle();
      expect(find.text('Startup not measured'), findsOneWidget);
    });

    testWidgets('no overflow errors in widget tree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PerfRadarView())),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('TracesTab', () {
    TraceSnapshot buildSnapshot({
      List<MapEntry<TraceKey, SpanKeyStatsSnapshot>> entries = const [],
    }) {
      return TraceSnapshot(stats: Map.fromEntries(entries), totalDropCount: 0);
    }

    SpanKeyStatsSnapshot buildStats({
      required String name,
      String? category,
      int count = 1,
      int meanMicros = 1000,
      int errorCount = 0,
    }) {
      final hist = LatencyHistogram();
      for (var i = 0; i < count; i++) {
        hist.record(meanMicros);
      }
      final snapshot = hist.snapshot();
      return SpanKeyStatsSnapshot(
        key: TraceKey(name: name, category: category),
        count: count,
        errorCount: errorCount,
        histogram: snapshot,
        outliers: const [],
        firstStartMicros: 0,
        lastStartMicros: count > 1 ? 1000000 : 0,
      );
    }

    testWidgets('shows empty state when snapshot is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TracesTab(snapshot: buildSnapshot())),
        ),
      );
      expect(find.textContaining('No spans recorded'), findsOneWidget);
    });

    testWidgets('renders a row for each span key', (tester) async {
      final snapshot = buildSnapshot(
        entries: [
          MapEntry(
            const TraceKey(name: 'db.query', category: 'db'),
            buildStats(name: 'db.query', category: 'db'),
          ),
          MapEntry(
            const TraceKey(name: 'http.get', category: 'http'),
            buildStats(name: 'http.get', category: 'http'),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TracesTab(snapshot: snapshot)),
        ),
      );

      expect(find.textContaining('db.query'), findsOneWidget);
      expect(find.textContaining('http.get'), findsOneWidget);
    });

    testWidgets('shows HOT tag for duplicate-suspect key', (tester) async {
      // Build a key with high count + tight inter-call interval
      final hist = LatencyHistogram();
      for (var i = 0; i < 15; i++) {
        hist.record(500); // fast calls
      }
      // firstStart=0, lastStart=100ms → 100ms / 14 gaps ≈ 7ms interval < 500ms
      final stats = SpanKeyStatsSnapshot(
        key: const TraceKey(name: 'hot.op', category: 'test'),
        count: 15,
        errorCount: 0,
        histogram: hist.snapshot(),
        outliers: const [],
        firstStartMicros: 0,
        lastStartMicros: 100000, // 100ms window → ~7ms avg interval
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TracesTab(
              snapshot: TraceSnapshot(
                stats: {stats.key: stats},
                totalDropCount: 0,
              ),
            ),
          ),
        ),
      );

      expect(find.text('HOT'), findsOneWidget);
    });

    testWidgets('search filters to matching operations', (tester) async {
      final snapshot = buildSnapshot(
        entries: [
          MapEntry(
            const TraceKey(name: 'db.query', category: 'db'),
            buildStats(name: 'db.query', category: 'db'),
          ),
          MapEntry(
            const TraceKey(name: 'http.get', category: 'http'),
            buildStats(name: 'http.get', category: 'http'),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TracesTab(snapshot: snapshot)),
        ),
      );

      // Type in the search field
      await tester.enterText(find.byType(TextField), 'db');
      await tester.pump();

      expect(find.textContaining('db.query'), findsOneWidget);
      expect(find.textContaining('http.get'), findsNothing);
    });

    testWidgets('search-to-zero shows empty state', (tester) async {
      final snapshot = buildSnapshot(
        entries: [
          MapEntry(
            const TraceKey(name: 'db.query', category: 'db'),
            buildStats(name: 'db.query', category: 'db'),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TracesTab(snapshot: snapshot)),
        ),
      );

      await tester.enterText(find.byType(TextField), 'zzznomatch');
      await tester.pump();

      expect(find.textContaining('No operations match'), findsOneWidget);
    });

    testWidgets('shows error marker for keys with errors', (tester) async {
      final stats = buildStats(name: 'broken.op', errorCount: 3);
      final snapshot = TraceSnapshot(
        stats: {stats.key: stats},
        totalDropCount: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TracesTab(snapshot: snapshot)),
        ),
      );
      await tester.pumpAndSettle();

      // '3 err' appears in the second line of the op cell.
      // The error count is also shown in the header column.
      expect(
        find.textContaining('err'),
        findsWidgets,
        reason: 'expected at least one "err" label for errorCount=3',
      );
    });

    testWidgets('column header has sortable op/count/avg/p95/total/intvl', (
      tester,
    ) async {
      final snapshot = buildSnapshot(
        entries: [
          MapEntry(
            const TraceKey(name: 'some.op', category: null),
            buildStats(name: 'some.op'),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TracesTab(snapshot: snapshot)),
        ),
      );

      // All 6 column headers must exist
      for (final label in ['op', 'count', 'avg', 'p95', 'total', 'intvl']) {
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'column header "$label" not found',
        );
      }
    });

    testWidgets('tapping a sort header toggles direction', (tester) async {
      final snapshot = buildSnapshot(
        entries: [
          MapEntry(
            const TraceKey(name: 'a', category: null),
            buildStats(name: 'a', count: 5),
          ),
          MapEntry(
            const TraceKey(name: 'b', category: null),
            buildStats(name: 'b', count: 10),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TracesTab(snapshot: snapshot)),
        ),
      );

      // Tap count header twice to toggle ascending
      final countHeader = find.text('count');
      await tester.tap(countHeader);
      await tester.pump();
      // Arrow should appear (↓ descending by default)
      expect(find.text('↓'), findsOneWidget);

      await tester.tap(countHeader);
      await tester.pump();
      expect(find.text('↑'), findsOneWidget);
    });
  });

  group('TraceDetailScreen', () {
    SpanKeyStatsSnapshot buildDetailStats({
      String name = 'test.op',
      String? category,
      int count = 5,
      int meanMicros = 1500,
    }) {
      final hist = LatencyHistogram();
      for (var i = 0; i < count; i++) {
        hist.record(meanMicros + i * 100);
      }
      return SpanKeyStatsSnapshot(
        key: TraceKey(name: name, category: category),
        count: count,
        errorCount: 0,
        histogram: hist.snapshot(),
        outliers: const [],
        firstStartMicros: 0,
        lastStartMicros: count > 1 ? 2000000 : 0,
      );
    }

    testWidgets('renders metric grid with 6 tiles', (tester) async {
      final stats = buildDetailStats();
      await tester.pumpWidget(
        MaterialApp(home: TraceDetailScreen(stats: stats)),
      );

      for (final label in ['avg', 'p95', 'total', 'p99', 'max', 'intvl']) {
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'metric tile "$label" not found',
        );
      }
    });

    testWidgets('shows call count in detail header', (tester) async {
      final stats = buildDetailStats(count: 7);
      await tester.pumpWidget(
        MaterialApp(home: TraceDetailScreen(stats: stats)),
      );
      await tester.pump();
      // The call count appears in the row below the app bar — either as
      // '7 calls' alone (rate unavailable) or '7 calls · N/s'.
      expect(find.textContaining('calls'), findsOneWidget);
    });

    testWidgets('shows category when present', (tester) async {
      final stats = buildDetailStats(category: 'db');
      await tester.pumpWidget(
        MaterialApp(home: TraceDetailScreen(stats: stats)),
      );
      expect(find.text('db'), findsOneWidget);
    });
  });

  group('StartupTab - not-measured state', () {
    testWidgets('shows not-measured when snapshot has no startup key', (
      tester,
    ) async {
      final snapshot = TraceSnapshot(stats: const {}, totalDropCount: 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StartupTab(snapshot: snapshot)),
        ),
      );
      expect(find.text('Startup not measured'), findsOneWidget);
      expect(find.textContaining('runApp'), findsOneWidget);
    });

    testWidgets('shows measured state when startup span is present', (
      tester,
    ) async {
      final hist = LatencyHistogram()..record(450000); // 450ms startup
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
      expect(find.text('Startup not measured'), findsNothing);
      expect(find.text('Time to first frame'), findsOneWidget);
    });
  });

  group('RebuildsTab', () {
    TraceSnapshot rebuildSnapshot(List<(String, int)> labels) {
      final map = <TraceKey, SpanKeyStatsSnapshot>{};
      for (final (label, count) in labels) {
        final hist = LatencyHistogram();
        for (var i = 0; i < count; i++) {
          hist.record(100);
        }
        final key = TraceKey(name: 'rebuild:$label', category: null);
        map[key] = SpanKeyStatsSnapshot(
          key: key,
          count: count,
          errorCount: 0,
          histogram: hist.snapshot(),
          outliers: const [],
          firstStartMicros: 0,
          lastStartMicros: 0,
        );
      }
      return TraceSnapshot(stats: map, totalDropCount: 0);
    }

    testWidgets('shows empty state when no rebuild spans', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RebuildsTab(
              snapshot: TraceSnapshot(stats: const {}, totalDropCount: 0),
            ),
          ),
        ),
      );
      expect(find.textContaining('TracedSubtree'), findsOneWidget);
    });

    testWidgets('shows EXCESSIVE tag for high-rebuild subtrees', (
      tester,
    ) async {
      final snapshot = rebuildSnapshot([('chat_list', 75)]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RebuildsTab(snapshot: snapshot)),
        ),
      );
      expect(find.text('EXCESSIVE'), findsOneWidget);
    });

    testWidgets('does not show EXCESSIVE for low rebuild count', (
      tester,
    ) async {
      final snapshot = rebuildSnapshot([('header', 3)]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RebuildsTab(snapshot: snapshot)),
        ),
      );
      expect(find.text('EXCESSIVE'), findsNothing);
    });

    testWidgets('renders each label as a row', (tester) async {
      final snapshot = rebuildSnapshot([('feed', 10), ('sidebar', 5)]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RebuildsTab(snapshot: snapshot)),
        ),
      );
      expect(find.text('feed'), findsOneWidget);
      expect(find.text('sidebar'), findsOneWidget);
    });
  });
}
