// test/engine/graph_scan_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/graph_scan.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/graph_scan_runner.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';

import '../support/fake_heap_probe.dart';

// ---------------------------------------------------------------------------
// Minimal HeapGraphView with a _Timer → MyLeakyWidget×2 topology.
//
// Graph:  root(0) → _Timer(1) → MyLeakyWidget(2)
//                             → MyLeakyWidget(3)
//
// Nodes 2 & 3 share the same timer-rooted signature → cluster of size 2.
// ---------------------------------------------------------------------------
final class _TimerRetentionGraph implements HeapGraphView {
  @override
  final int rootId = 0;

  @override
  final int nodeCount = 4; // ids 0..3

  static final Uri _dartAsync = Uri.parse('dart:async');
  static final Uri _appLib = Uri.parse('package:myapp/src/widget.dart');

  @override
  HeapNode node(int id) => switch (id) {
    0 => HeapNode(
      id: 0,
      className: 'GCRoot',
      libraryUri: _dartAsync,
      shallowSize: 0,
      edges: [const HeapEdge(targetId: 1, field: '_timer')],
    ),
    1 => HeapNode(
      id: 1,
      className: '_Timer',
      libraryUri: _dartAsync,
      shallowSize: 8,
      edges: [
        const HeapEdge(targetId: 2, field: '_callback'),
        const HeapEdge(targetId: 3, field: '_callback'),
      ],
    ),
    2 => HeapNode(
      id: 2,
      className: 'MyLeakyWidget',
      libraryUri: _appLib,
      shallowSize: 64,
      edges: const [],
    ),
    3 => HeapNode(
      id: 3,
      className: 'MyLeakyWidget',
      libraryUri: _appLib,
      shallowSize: 64,
      edges: const [],
    ),
    _ => throw StateError('id $id out of range'),
  };
}

// ---------------------------------------------------------------------------
// Fake graph-scan runners (analyse the synthetic graph directly; no isolate)
// ---------------------------------------------------------------------------

/// Analyses the Timer-retention graph on every [run] call.
final class _LeakGraphRunner implements GraphScanRunner {
  int runCount = 0;

  @override
  Future<GraphAnalysisResult?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  }) async {
    runCount++;
    return GraphLeakAnalyzer().analyze(_TimerRetentionGraph(), options);
  }
}

/// Always returns null (simulates unavailable / size-exceeded graph).
final class _NullGraphRunner implements GraphScanRunner {
  @override
  Future<GraphAnalysisResult?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  }) async => null;
}

/// Throws on run.
final class _ThrowingGraphRunner implements GraphScanRunner {
  @override
  Future<GraphAnalysisResult?> run(
    GraphAnalysisOptions options, {
    required int maxObjects,
  }) async => throw StateError('graph runner failure');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LeakEngine _makeEngine({
  required GraphScanRunner graphRunner,
  required GraphScan graphScan,
}) => LeakEngine(
  probe: FakeHeapProbe([]),
  analyzer: LeakAnalyzer(SuspectSet.empty()),
  config: LeakRadarConfig(
    autoScan: const AutoScan(
      onNavigation: true,
      navigationDebounce: Duration(milliseconds: 10),
    ),
    graphScan: graphScan,
  ),
  graphRunner: graphRunner,
);

/// Fires [count] navigation pops through the engine's observer and waits for
/// the debounce + a bit of scheduling slack to elapse.
Future<void> _navigate(LeakEngine engine, {int count = 1}) async {
  for (var i = 0; i < count; i++) {
    engine.navigatorObserver?.didPop(
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
      null,
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 80));
}

void main() {
  group('LeakEngine graph scan', () {
    test(
      'graph scan runs on the Nth navigation and finding appears in report',
      () async {
        final graphRunner = _LeakGraphRunner();
        final engine = _makeEngine(
          graphRunner: graphRunner,
          graphScan: const GraphScan(
            everyNthNavigation: 3,
            maxGraphObjects: 100000,
            appPackages: ['myapp'],
            minClusterSize: 2,
          ),
        );

        final reports = <LeakReport>[];
        engine.reports.listen(reports.add);
        await engine.start();

        // Navigations 1 & 2: no graph scan.
        await _navigate(engine, count: 1);
        await _navigate(engine, count: 1);

        expect(graphRunner.runCount, 0, reason: 'no graph scan before Nth nav');

        // Navigation 3: graph scan fires.
        await _navigate(engine, count: 1);

        await engine.stop();

        expect(
          graphRunner.runCount,
          1,
          reason: 'run called once on the 3rd navigation',
        );

        final graphReport = reports.lastWhere(
          (r) =>
              r.findings.any((f) => f.kind == LeakKind.retainedByNonLiveRoot),
          orElse: () =>
              throw TestFailure('no report with retainedByNonLiveRoot finding'),
        );
        expect(
          graphReport.findings.any(
            (f) =>
                f.kind == LeakKind.retainedByNonLiveRoot &&
                f.className == 'MyLeakyWidget',
          ),
          isTrue,
          reason: 'MyLeakyWidget cluster must appear as a finding',
        );
      },
    );

    test('graph scan does NOT run on non-Nth navigations', () async {
      final graphRunner = _LeakGraphRunner();
      final engine = _makeEngine(
        graphRunner: graphRunner,
        graphScan: const GraphScan(
          everyNthNavigation: 5,
          maxGraphObjects: 100000,
          minClusterSize: 2,
        ),
      );

      await engine.start();

      // 4 navigations — none is the 5th.
      await _navigate(engine, count: 1);
      await _navigate(engine, count: 1);
      await _navigate(engine, count: 1);
      await _navigate(engine, count: 1);

      await engine.stop();

      expect(
        graphRunner.runCount,
        0,
        reason: 'graph run must not be called before the 5th nav',
      );
    });

    test(
      'null-returning runner degrades gracefully — normal report emitted',
      () async {
        final engine = _makeEngine(
          graphRunner: _NullGraphRunner(),
          graphScan: const GraphScan(
            everyNthNavigation: 1,
            maxGraphObjects: 100000,
            minClusterSize: 2,
          ),
        );

        final reports = <LeakReport>[];
        engine.reports.listen(reports.add);
        await engine.start();

        await _navigate(engine, count: 1);
        await engine.stop();

        // Must have emitted at least one report (normal nav report).
        expect(reports, isNotEmpty);
        // Must NOT have any graph findings (null runner → no clusters).
        expect(
          reports.any(
            (r) =>
                r.findings.any((f) => f.kind == LeakKind.retainedByNonLiveRoot),
          ),
          isFalse,
          reason: 'null runner must not produce graph findings',
        );
      },
    );

    test('throwing runner degrades gracefully — engine never throws', () async {
      final engine = _makeEngine(
        graphRunner: _ThrowingGraphRunner(),
        graphScan: const GraphScan(
          everyNthNavigation: 1,
          maxGraphObjects: 100000,
          minClusterSize: 2,
        ),
      );

      await engine.start();
      // Must not throw even though the runner throws.
      await expectLater(() => _navigate(engine, count: 1), returnsNormally);
      await engine.stop();
    });

    test('pre-write gate skips the graph scan when the heap exceeds '
        'maxGraphObjects', () async {
      final graphRunner = _LeakGraphRunner();
      // A captured snapshot whose live-object total (200k) exceeds the 100k
      // cap, so the scan must be skipped BEFORE the runner is ever called.
      final bigHeap = HeapSnapshot(
        capturedAt: DateTime(2026),
        samples: [
          ClassSample(
            className: 'SomeClass',
            instancesCurrent: 200000,
            bytesCurrent: 0,
            timestamp: DateTime(2026),
          ),
        ],
      );
      final engine = LeakEngine(
        probe: FakeHeapProbe([bigHeap]),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
        config: const LeakRadarConfig(
          autoScan: AutoScan(
            onNavigation: true,
            navigationDebounce: Duration(milliseconds: 10),
          ),
          graphScan: GraphScan(
            everyNthNavigation: 1,
            maxGraphObjects: 100000,
            minClusterSize: 2,
          ),
        ),
        graphRunner: graphRunner,
      );

      await engine.start();
      await _navigate(engine, count: 1);
      await engine.stop();

      expect(
        graphRunner.runCount,
        0,
        reason: 'no snapshot write/parse when the heap is over the cap',
      );
    });

    test('cooldown blocks back-to-back navigation graph scans', () async {
      final graphRunner = _LeakGraphRunner();
      // FakeHeapProbe([]) → empty samples → latestObjectTotal 0, so the size
      // gate never fires; only the cooldown can suppress the second scan.
      final engine = _makeEngine(
        graphRunner: graphRunner,
        graphScan: const GraphScan(
          everyNthNavigation: 1,
          maxGraphObjects: 100000,
          minClusterSize: 2,
        ),
      );

      await engine.start();
      // Every nav triggers (everyNth=1) but all fall inside the 30s cooldown.
      await _navigate(engine, count: 1);
      await _navigate(engine, count: 1);
      await _navigate(engine, count: 1);
      await engine.stop();

      expect(
        graphRunner.runCount,
        1,
        reason: 'cooldown allows only the first back-to-back graph scan',
      );
    });

    test('graphScan null disables graph scanning entirely', () async {
      final graphRunner = _LeakGraphRunner();
      final engine = LeakEngine(
        probe: FakeHeapProbe([]),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
        config: const LeakRadarConfig(
          autoScan: AutoScan(
            onNavigation: true,
            navigationDebounce: Duration(milliseconds: 10),
          ),
        ),
        graphRunner: graphRunner,
      );

      await engine.start();
      await _navigate(engine, count: 5);
      await engine.stop();

      expect(
        graphRunner.runCount,
        0,
        reason: 'null graphScan must never call run',
      );
    });
  });
}
