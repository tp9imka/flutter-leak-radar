import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:path/path.dart' as p;
import 'package:radar_desktop/src/seams/file_snapshot_store.dart';
import 'package:radar_desktop/src/workspace/workspace_controller.dart';
import 'package:radar_workbench/radar_workbench.dart';

SnapshotBundle _bundle(
  String label, {
  List<GraphLeakCluster> clusters = const [],
}) => SnapshotBundle(
  capturedAt: DateTime(2026, 1, 1),
  label: label,
  histogram: const [],
  analysisResult: GraphAnalysisResult(
    clusters: clusters,
    stats: const GraphAnalysisStats(
      totalObjects: 0,
      reachableObjects: 0,
      leakCandidates: 0,
      clusters: 0,
      suppressedByAppFilter: 0,
      warnings: [],
    ),
  ),
);

GraphLeakCluster _cluster(String signature, String className) =>
    GraphLeakCluster(
      className: className,
      libraryUri: Uri.parse('package:my_app/x.dart'),
      instanceCount: 1,
      retainedShallowBytes: 10,
      representativePath: const GraphRetainingPath(
        hops: [GraphHop(className: 'Owner')],
        rootKind: RootKind.stream,
      ),
      rootKind: RootKind.stream,
      confidence: LeakConfidence.heuristic,
      signature: signature,
    );

/// A [FileSnapshotStore] that records the sessions it is asked to persist
/// without touching disk, so a test can assert exactly what would be written.
class _RecordingStore extends FileSnapshotStore {
  final List<PersistedSession> persisted = [];

  @override
  Future<PersistedSession?> restore() async => null;

  @override
  Future<void> persist(PersistedSession session) async {
    persisted.add(session);
  }

  @override
  Future<void> clear() async {}
}

void main() {
  test(
    'deleting the last dump persists the empty session (no resurrection)',
    () async {
      final store = _RecordingStore();
      final wc = WorkspaceController(store: store);
      // Realistic launch: restore runs first (nothing to restore here), which
      // is what arms persistence for empty states.
      await wc.restore();

      final a = wc.addExisting(_bundle('a'), source: DumpSource.file);
      wc.removeDump(a.id);

      // The empty state must be written so a relaunch does not resurrect the
      // deleted dump — the pre-fix guard skipped this.
      expect(store.persisted, isNotEmpty);
      expect(store.persisted.last.bundles, isEmpty);
    },
  );

  test('a triage-only session is written after restore completes', () async {
    final store = _RecordingStore();
    final wc = WorkspaceController(store: store);
    await wc.restore();

    wc.updateTriage(
      TriageStore.empty.acknowledge(
        'sigA',
        note: 'BUG-1',
        className: 'FixedLeak',
        now: DateTime(2026, 7, 1),
      ),
    );

    expect(store.persisted, isNotEmpty);
    expect(store.persisted.last.bundles, isEmpty);
    expect(store.persisted.last.triage.entryFor('sigA')?.note, 'BUG-1');
  });

  test(
    'a fresh, un-restored controller never clobbers with an empty persist',
    () async {
      final store = _RecordingStore();
      final wc = WorkspaceController(store: store);

      // No restore yet: an empty-state mutation must not overwrite a saved
      // session on disk.
      wc.clearAll();

      expect(store.persisted, isEmpty);
    },
  );

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

  test(
    'acknowledging a cluster persists the note and rehydrate restores it',
    () {
      final wc = WorkspaceController();
      wc.addExisting(
        _bundle('a', clusters: [_cluster('sigA', 'LeakyThing')]),
        source: DumpSource.file,
      );
      // The synchronous fold in _persist runs before its first await, so the
      // acked store is reflected in toSession immediately.
      wc.updateTriage(
        wc.triage.acknowledge('sigA', note: 'BUG-1', now: DateTime(2026, 7, 1)),
      );
      final session = wc.toSession();
      expect(
        session.triage.entryFor('sigA')!.status,
        TriageStatus.acknowledged,
      );
      expect(session.triage.entryFor('sigA')!.note, 'BUG-1');

      final wc2 = WorkspaceController();
      wc2.rehydrate(session);
      expect(wc2.triage.entryFor('sigA')!.note, 'BUG-1');
    },
  );

  test('restore surfaces a newer-schema refusal', () async {
    final dir = Directory.systemTemp.createTempSync('radar_wc_refusal');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    File(p.join(dir.path, 'radar_desktop_session.json')).writeAsStringSync(
      jsonEncode({
        'version': kSessionSchemaVersion + 1,
        'bundles': const <Object?>[],
        'selectedIds': const <Object?>[],
        'view': 'leakClusters',
      }),
    );
    final wc = WorkspaceController(
      store: FileSnapshotStore(directory: () async => dir),
    );

    await wc.restore();

    expect(wc.restoreRefusal, isNotNull);
    expect(wc.restoreRefusal, contains('newer'));
  });

  test(
    'restore seeds triage from a bundle-less (triage-only) session',
    () async {
      final dir = Directory.systemTemp.createTempSync('radar_wc_triage_only');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      // A session with recorded fixes but no dumps left.
      final triage = TriageStore.empty.acknowledge(
        'sigA',
        note: 'BUG-1',
        className: 'FixedLeak',
        now: DateTime(2026, 7, 1),
      );
      File(p.join(dir.path, 'radar_desktop_session.json')).writeAsStringSync(
        jsonEncode(
          PersistedSession(
            bundles: const [],
            selectedIds: const [],
            view: RadarView.leakClusters,
            triage: triage,
          ).toJson(),
        ),
      );
      final wc = WorkspaceController(
        store: FileSnapshotStore(directory: () async => dir),
      );

      await wc.restore();

      // The triage baseline is seeded even though no bundles rehydrated.
      expect(wc.triage.entryFor('sigA')!.note, 'BUG-1');
      expect(wc.memory.snapshots, isEmpty);
    },
  );
}
