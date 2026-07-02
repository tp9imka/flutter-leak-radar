import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

// ── Harness ─────────────────────────────────────────────────────────────────

MemoryController _controller() => MemoryController(
  snapshotSource: FakeSnapshotSource(),
  connection: FakeRadarConnection(),
);

// ── Fixtures ────────────────────────────────────────────────────────────────

ClassCount _cc(
  String name, {
  int inst = 10,
  int bytes = 1024,
  String lib = 'package:app/src/x.dart',
}) => ClassCount(
  className: name,
  libraryUri: Uri.parse(lib),
  instanceCount: inst,
  shallowBytes: bytes,
);

GraphAnalysisResult _analysis(
  List<ClassRootProfile> profiles, {
  List<ClassPathDistribution> distributions = const [],
}) => GraphAnalysisResult(
  clusters: const [],
  stats: const GraphAnalysisStats(
    totalObjects: 0,
    reachableObjects: 0,
    leakCandidates: 0,
    clusters: 0,
    suppressedByAppFilter: 0,
    warnings: [],
  ),
  classRootProfiles: profiles,
  classPathDistributions: distributions,
);

ClassRootProfile _profile(
  String name,
  Map<RootKind, int> byRoot, {
  GraphRetainingPath? path,
  int bytes = 2048,
}) => ClassRootProfile(
  className: name,
  libraryUri: Uri.parse('package:app/src/$name.dart'),
  totalInstances: byRoot.values.fold(0, (a, b) => a + b),
  retainedShallowBytes: bytes,
  byRoot: byRoot,
  representativePath: path,
);

SnapshotBundle _snap(
  int id, {
  List<ClassCount>? hist,
  List<ClassRootProfile> profiles = const [],
  List<ClassPathDistribution> distributions = const [],
}) => SnapshotBundle(
  id: id,
  capturedAt: DateTime(2026, 1, 1, 12, 0, id),
  label: 'Snapshot $id',
  histogram: hist ?? [_cc('Foo'), _cc('Bar')],
  analysisResult: _analysis(profiles, distributions: distributions),
);

/// An unassigned-id bundle (as a file-import path would build), for
/// [MemoryController.addBundle] tests where the id is assigned by the
/// controller rather than the fixture.
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

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('MemoryController', () {
    test('toggleSelection keeps at most two, dropping the oldest', () {
      final c = _controller()
        ..debugAdd(_snap(1))
        ..debugAdd(_snap(2))
        ..debugAdd(_snap(3));
      c.toggleSelection(1);
      c.toggleSelection(2);
      c.toggleSelection(3);
      expect(c.isSelected(1), isFalse);
      expect(c.isSelected(2), isTrue);
      expect(c.isSelected(3), isTrue);
    });

    test('re-notifies its listeners when the VM connection changes', () {
      // Regression: Capture stayed disabled until the user re-navigated, because
      // the toolbar (gated on canCapture, derived from the connection) never
      // repainted when the connection became ready after first paint.
      final connection = FakeRadarConnection();
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: connection,
      );
      var ticks = 0;
      c.addListener(() => ticks++);
      connection.set(
        state: const RadarConnectionState(
          phase: RadarConnectionPhase.connected,
        ),
      );
      expect(ticks, 1);
    });

    test('pair is ordered oldest→newest regardless of selection order', () {
      final c = _controller()
        ..debugAdd(_snap(1))
        ..debugAdd(_snap(2));
      c.toggleSelection(2);
      c.toggleSelection(1);
      final pair = c.pair;
      expect(pair, isNotNull);
      expect(pair!.baseline.id, 1);
      expect(pair.comparison.id, 2);
    });

    test('diff computes growth between the selected pair', () {
      final c = _controller()
        ..debugAdd(_snap(1, hist: [_cc('Foo', inst: 5)]))
        ..debugAdd(_snap(2, hist: [_cc('Foo', inst: 15)]));
      c.toggleSelection(1);
      c.toggleSelection(2);
      final diff = c.diff;
      expect(diff, isNotNull);
      final foo = diff!.firstWhere((d) => d.after.className == 'Foo');
      expect(foo.instanceDelta, 10);
    });

    test('a single selected snapshot diffs against an empty baseline', () {
      final c = _controller()
        ..debugAdd(
          _snap(
            1,
            hist: [
              _cc('Foo', inst: 5, bytes: 100),
              _cc('Bar', inst: 2, bytes: 40),
            ],
          ),
        );
      c.toggleSelection(1);
      expect(c.pair, isNull);
      expect(c.comparingAgainstEmpty, isTrue);
      expect(c.comparison?.id, 1);
      final diff = c.diff;
      expect(diff, isNotNull);
      final foo = diff!.firstWhere((d) => d.after.className == 'Foo');
      expect(foo.before.instanceCount, 0); // empty baseline
      expect(foo.instanceDelta, 5); // full count shown as growth from nothing
      expect(foo.bytesDelta, 100);
    });

    test('no selection yields no comparison and no diff', () {
      final c = _controller()..debugAdd(_snap(1));
      // debugAdd does not auto-select (only capture() does).
      expect(c.comparison, isNull);
      expect(c.comparingAgainstEmpty, isFalse);
      expect(c.diff, isNull);
    });

    test('two selected snapshots are a delta, not an empty baseline', () {
      final c = _controller()
        ..debugAdd(_snap(1))
        ..debugAdd(_snap(2));
      c.toggleSelection(1);
      c.toggleSelection(2);
      expect(c.comparingAgainstEmpty, isFalse);
      expect(c.comparison?.id, 2);
    });

    test('remove drops the snapshot and deselects it', () {
      final c = _controller()
        ..debugAdd(_snap(1))
        ..debugAdd(_snap(2));
      c.toggleSelection(1);
      c.toggleSelection(2);
      c.remove(1);
      expect(c.snapshots.length, 1);
      expect(c.isSelected(1), isFalse);
      expect(c.pair, isNull);
    });

    test('focused is the comparison when paired, else the latest', () {
      final c = _controller()
        ..debugAdd(_snap(1))
        ..debugAdd(_snap(2))
        ..debugAdd(_snap(3));
      expect(c.focused?.id, 3); // latest
      c.toggleSelection(1);
      c.toggleSelection(2);
      expect(c.focused?.id, 2); // comparison of {1,2}
    });

    test('clearAll empties the list and selection', () {
      final c = _controller()..debugAdd(_snap(1));
      c.toggleSelection(1);
      c.clearAll();
      expect(c.hasSnapshots, isFalse);
      expect(c.pair, isNull);
    });

    test('SnapshotBundle JSON round-trips (export)', () {
      final b = _snap(
        7,
        hist: [_cc('Foo', inst: 3)],
        profiles: [
          _profile('Foo', {RootKind.stream: 3}),
        ],
      );
      final restored = SnapshotBundle.fromJson(b.toJson());
      expect(restored.id, 7);
      expect(restored.label, 'Snapshot 7');
      expect(restored.histogram.single.className, 'Foo');
      expect(restored.analysisResult.classRootProfiles.single.className, 'Foo');
    });
  });

  group('Session persistence', () {
    test('persistableSnapshots keeps only the most recent 8', () {
      final c = _controller();
      for (var i = 1; i <= 9; i++) {
        c.debugAdd(_snap(i));
      }
      final kept = c.persistableSnapshots;
      expect(kept.length, 8);
      expect(kept.first.id, 2); // oldest (id 1) dropped
      expect(kept.last.id, 9);
    });

    test('rehydrate restores bundles, selection and the restored flag', () {
      final c = _controller();
      final session = PersistedSession(
        bundles: [_snap(4), _snap(7)],
        selectedIds: const [7, 99], // 99 no longer exists → filtered out
        view: RadarView.classHistogram,
      );
      c.rehydrate(session);
      expect(c.snapshots.map((s) => s.id), [4, 7]);
      expect(c.isSelected(7), isTrue);
      expect(c.isSelected(99), isFalse);
      expect(c.restoredFromDisk, isTrue);
    });

    test('rehydrate ignores an empty session', () {
      final c = _controller();
      c.rehydrate(
        const PersistedSession(
          bundles: [],
          selectedIds: [],
          view: RadarView.snapshotDiff,
        ),
      );
      expect(c.hasSnapshots, isFalse);
      expect(c.restoredFromDisk, isFalse);
    });

    test('flush writes the current bundles, selection and view', () async {
      final store = InMemorySnapshotStore();
      final c = _controller()
        ..debugAdd(_snap(1))
        ..debugAdd(_snap(2));
      c.toggleSelection(2);
      final p = SessionPersistence(
        store: store,
        memory: c,
        readView: () => RadarView.classHistogram,
      );
      await p.flush();
      expect(store.last, isNotNull);
      expect(store.last!.bundles.map((b) => b.id), [1, 2]);
      expect(store.last!.selectedIds, [2]);
      expect(store.last!.view, RadarView.classHistogram);
    });

    test('start persists after a mutation, debounced', () async {
      final store = InMemorySnapshotStore();
      final c = _controller();
      final p = SessionPersistence(
        store: store,
        memory: c,
        readView: () => RadarView.snapshotDiff,
        debounce: const Duration(milliseconds: 10),
      )..start();
      addTearDown(p.dispose);
      c.debugAdd(_snap(1));
      expect(store.persistCount, 0); // not yet — debounced
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(store.persistCount, greaterThanOrEqualTo(1));
      expect(store.last!.bundles.single.id, 1);
    });

    test('a session round-trips through the store', () async {
      final store = InMemorySnapshotStore();
      final src = _controller()
        ..debugAdd(_snap(1, hist: [_cc('Foo', inst: 3)]))
        ..debugAdd(_snap(2));
      src.toggleSelection(1);
      await SessionPersistence(
        store: store,
        memory: src,
        readView: () => RadarView.retainingPaths,
      ).flush();

      final dst = _controller();
      final loaded = await SessionPersistence(
        store: store,
        memory: dst,
        readView: () => RadarView.snapshotDiff,
      ).load();
      expect(loaded, isNotNull);
      dst.rehydrate(loaded!);
      expect(dst.snapshots.length, 2);
      expect(dst.isSelected(1), isTrue);
      expect(dst.restoredFromDisk, isTrue);
      expect(loaded.view, RadarView.retainingPaths);
    });

    test('PersistedSession JSON round-trips', () {
      final s = PersistedSession(
        bundles: [
          _snap(1, hist: [_cc('Foo')]),
        ],
        selectedIds: const [1],
        view: RadarView.classHistogram,
      );
      final restored = PersistedSession.fromJson(s.toJson());
      expect(restored.bundles.single.id, 1);
      expect(restored.selectedIds, [1]);
      expect(restored.view, RadarView.classHistogram);
    });
  });

  group('addBundle (desktop import path)', () {
    test('assigns sequential ids, appends, and auto-selects the first two', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      final a = c.addBundle(_bundle('a'));
      final b = c.addBundle(_bundle('b'));
      final third = c.addBundle(_bundle('c'));

      expect(c.snapshots.map((s) => s.label), ['a', 'b', 'c']);
      expect(a.id, 1);
      expect(b.id, 2);
      expect(third.id, 3);
      // First two auto-selected; third not (selection caps at 2).
      expect(c.selectedIds, [1, 2]);
    });

    test('ids from addBundle do not collide with a later capture id', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      c.addBundle(_bundle('a'));
      final b = c.addBundle(_bundle('b'));
      expect(b.id, 2);
      expect(c.byId(2)?.label, 'b');
    });
  });

  group('focusOn (desktop active-dump hook)', () {
    test('focused honors an explicitly focused id over latest', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      final a = c.addBundle(_bundle('a'));
      final b = c.addBundle(_bundle('b')); // b is latest
      // addBundle auto-selects the first two ids for diffing (existing
      // behavior); deselect both so `pair` is null here and `focused` falls
      // through to `latest`, isolating focusOn's own fallback chain.
      c.toggleSelection(a.id);
      c.toggleSelection(b.id);
      // Default: focused falls through to latest (b), not a.
      expect(c.focused?.label, 'b');
      c.focusOn(a.id);
      expect(c.focusedId, a.id);
      expect(c.focused?.label, 'a'); // now honors the explicit focus
      c.focusOn(null);
      expect(c.focused?.label, 'b'); // cleared → back to latest
    });

    test('focusOn(unknown id) falls through to pair/latest', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      final a = c.addBundle(_bundle('a'));
      final b = c.addBundle(_bundle('b'));
      // Deselect both so `pair` is null; isolates the fallback to `latest`.
      c.toggleSelection(a.id);
      c.toggleSelection(b.id);
      c.focusOn(9999); // not present
      expect(c.focused?.id, b.id); // _byId(9999) == null → latest
    });

    test('remove(id) reconciles a focused id pointing at the removed '
        'snapshot', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      final a = c.addBundle(_bundle('a'));
      final b = c.addBundle(_bundle('b')); // b is latest
      // Deselect both so `pair` is null and `focused` falls through to
      // `latest` once the explicit focus is gone.
      c.toggleSelection(a.id);
      c.toggleSelection(b.id);
      c.focusOn(a.id);
      c.remove(a.id);
      expect(c.focusedId, isNull);
      expect(c.focused?.id, b.id); // falls back to latest, not a stale id
    });

    test('clearAll() clears a previously focused id', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      final a = c.addBundle(_bundle('a'));
      c.focusOn(a.id);
      c.clearAll();
      expect(c.focusedId, isNull);
    });

    test('rehydrate() clears the focused id so it cannot collide with a '
        'same-numbered snapshot in the restored session', () {
      final c = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: FakeRadarConnection(),
      );
      final a = c.addBundle(_bundle('a')); // assigned id 1
      c.focusOn(a.id);
      c.rehydrate(
        PersistedSession(
          bundles: [_snap(1), _snap(2)], // unrelated new id-1 snapshot
          selectedIds: const [2],
          view: RadarView.snapshotDiff,
        ),
      );
      expect(c.focusedId, isNull);
      // Without the fix, `focused` would resolve to the new session's id-1
      // snapshot purely by numeric coincidence with the old focus.
      expect(c.focused?.id, 2); // latest of the restored session
    });
  });
}
