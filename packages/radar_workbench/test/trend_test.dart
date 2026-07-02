import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';

SnapshotBundle _b(DateTime at, Map<String, int> counts) => SnapshotBundle(
  capturedAt: at,
  label: at.toIso8601String(),
  histogram: [
    for (final e in counts.entries)
      ClassCount(
        className: e.key,
        libraryUri: Uri.parse('package:app/app.dart'),
        instanceCount: e.value,
        shallowBytes: e.value * 10,
      ),
  ],
  analysisResult: const GraphAnalysisResult(
    clusters: [],
    stats: GraphAnalysisStats(
      totalObjects: 0,
      reachableObjects: 0,
      leakCandidates: 0,
      clusters: 0,
      suppressedByAppFilter: 0,
      warnings: [],
    ),
  ),
);

void main() {
  final t0 = DateTime(2026, 1, 1, 9);
  final t1 = DateTime(2026, 1, 1, 13);
  final t2 = DateTime(2026, 1, 1, 21);

  test('computeTrend sorts by capturedAt and reads per-class counts', () {
    // Deliberately out of order to prove sorting.
    final bundles = [
      _b(t2, {'Leaky': 42}),
      _b(t0, {'Leaky': 15}),
      _b(t1, {'Leaky': 24}),
    ];
    final s = computeTrend(bundles, 'Leaky');
    expect(s.className, 'Leaky');
    expect(s.points.map((p) => p.instanceCount), [15, 24, 42]);
    expect(s.points.map((p) => p.shallowBytes), [150, 240, 420]);
    expect(s.firstInstances, 15);
    expect(s.lastInstances, 42);
    expect(s.netInstanceDelta, 27);
  });

  test('absent class in a snapshot reads as 0, not dropped', () {
    final bundles = [
      _b(t0, {'Leaky': 5}),
      _b(t1, {'Other': 3}), // Leaky missing here
      _b(t2, {'Leaky': 9}),
    ];
    final s = computeTrend(bundles, 'Leaky');
    expect(s.points.map((p) => p.instanceCount), [5, 0, 9]);
  });

  test('growingClassNames returns classes that grew first→last', () {
    final bundles = [
      _b(t0, {'Grow': 1, 'Flat': 5, 'Shrink': 9}),
      _b(t1, {'Grow': 10, 'Flat': 5, 'Shrink': 2}),
    ];
    final names = growingClassNames(bundles);
    expect(names, contains('Grow'));
    expect(names, isNot(contains('Flat')));
    expect(names, isNot(contains('Shrink')));
  });
}
