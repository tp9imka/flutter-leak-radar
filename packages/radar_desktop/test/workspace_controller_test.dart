import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_desktop/src/workspace/workspace_controller.dart';
import 'package:radar_workbench/radar_workbench.dart';

SnapshotBundle _bundle(String label) => SnapshotBundle(
  capturedAt: DateTime(2026, 1, 1),
  label: label,
  histogram: const [],
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
  test('addExisting populates memory, focuses it, and records meta', () {
    final wc = WorkspaceController();
    final b = wc.addExisting(_bundle('soak-1'), source: DumpSource.file);
    expect(wc.memory.snapshots.single.id, b.id);
    expect(wc.memory.focusedId, b.id);
    expect(wc.dumps.single.label, 'soak-1');
    expect(wc.dumps.single.source, DumpSource.file);
  });

  test('toggleTrendSelection adds/removes ids', () {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
    final b = wc.addExisting(_bundle('b'), source: DumpSource.file);
    wc.toggleTrendSelection(a.id);
    wc.toggleTrendSelection(b.id);
    expect(wc.trendSelection, containsAll([a.id, b.id]));
    wc.toggleTrendSelection(a.id);
    expect(wc.trendSelection, isNot(contains(a.id)));
  });

  test('selectComparePair sets the memory 2-way selection', () {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
    final b = wc.addExisting(_bundle('b'), source: DumpSource.file);
    wc.selectComparePair(a.id, b.id);
    expect(wc.memory.selectedIds, containsAll([a.id, b.id]));
    expect(wc.memory.diff, isNotNull);
  });

  test('removeDump drops it from memory + meta + trend selection', () {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
    wc.toggleTrendSelection(a.id);
    wc.removeDump(a.id);
    expect(wc.memory.snapshots, isEmpty);
    expect(wc.dumps, isEmpty);
    expect(wc.trendSelection, isNot(contains(a.id)));
  });

  test('session round-trips bundles + meta through PersistedSession', () {
    final wc = WorkspaceController();
    final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
    final session = wc.toSession();
    expect(session.bundles.map((b) => b.id), contains(a.id));

    final wc2 = WorkspaceController();
    wc2.rehydrate(session);
    expect(wc2.memory.snapshots.map((s) => s.label), contains('a'));
    expect(wc2.dumps.map((d) => d.label), contains('a'));
  });
}
