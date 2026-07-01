import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import 'package:flutter_leak_radar_devtools/src/capture/snapshot_bundle.dart';
import 'package:flutter_leak_radar_devtools/src/capture/snapshot_service.dart';
import 'package:flutter_leak_radar_devtools/src/connection/connection_state_notifier.dart';
import 'package:flutter_leak_radar_devtools/src/memory/class_histogram_view.dart';
import 'package:flutter_leak_radar_devtools/src/memory/memory_controller.dart';
import 'package:flutter_leak_radar_devtools/src/memory/retaining_paths_view.dart';
import 'package:flutter_leak_radar_devtools/src/memory/snapshots_view.dart';
import 'package:flutter_leak_radar_devtools/src/presentation/retaining_path_tile.dart';
import 'package:flutter_leak_radar_devtools/src/session/session_persistence.dart';
import 'package:flutter_leak_radar_devtools/src/session/snapshot_store.dart';
import 'package:flutter_leak_radar_devtools/src/shell/connection_bar.dart';
import 'package:flutter_leak_radar_devtools/src/shell/left_rail.dart';
import 'package:flutter_leak_radar_devtools/src/shell/radar_view.dart';

// ── Harness ─────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(
  home: Theme(
    data: radarDarkTheme(),
    child: Scaffold(body: child),
  ),
);

Widget _wrapDesktop(Widget child) => MaterialApp(
  home: Theme(
    data: radarDarkTheme(),
    child: Scaffold(body: SizedBox(width: 1280, height: 800, child: child)),
  ),
);

void _setDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _FakeConnectionNotifier extends ConnectionStateNotifier {
  _FakeConnectionNotifier(this._fakeState);
  final ExtensionConnectionState _fakeState;
  @override
  ExtensionConnectionState get state => _fakeState;
  @override
  Future<void> init() async {}
}

MemoryController _controller() => MemoryController(
  service: const SnapshotService(),
  connection: _FakeConnectionNotifier(
    const ExtensionConnectionState(
      phase: ExtensionConnectionPhase.disconnected,
    ),
  ),
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

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('ConnectionBar', () {
    testWidgets('shows disconnected chip when not connected', (tester) async {
      final notifier = _FakeConnectionNotifier(
        const ExtensionConnectionState(
          phase: ExtensionConnectionPhase.disconnected,
        ),
      );
      await tester.pumpWidget(
        _wrap(SizedBox(height: 44, child: ConnectionBar(notifier: notifier))),
      );
      expect(find.text('disconnected'), findsOneWidget);
    });
  });

  group('LeftRail', () {
    testWidgets('renders three memory nav items with new label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 198,
            child: LeftRail(
              currentView: RadarView.snapshotDiff,
              onViewChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Snapshots'), findsOneWidget);
      expect(find.text('Class histogram'), findsOneWidget);
      expect(find.text('Retaining paths'), findsOneWidget);
    });

    testWidgets('tapping a nav item fires onViewChanged', (tester) async {
      RadarView? changed;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 198,
            child: LeftRail(
              currentView: RadarView.snapshotDiff,
              onViewChanged: (v) => changed = v,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Class histogram'));
      await tester.pump();
      expect(changed, RadarView.classHistogram);
    });
  });

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
        bundles: [_snap(1, hist: [_cc('Foo')])],
        selectedIds: const [1],
        view: RadarView.classHistogram,
      );
      final restored = PersistedSession.fromJson(s.toJson());
      expect(restored.bundles.single.id, 1);
      expect(restored.selectedIds, [1]);
      expect(restored.view, RadarView.classHistogram);
    });
  });

  group('SnapshotsView', () {
    testWidgets('no snapshots shows the idle capture hint', (tester) async {
      await tester.pumpWidget(_wrap(SnapshotsView(controller: _controller())));
      expect(find.text('Capture heap snapshots'), findsOneWidget);
      expect(find.text('Capture'), findsOneWidget);
    });

    testWidgets('a selected pair renders the diff table', (tester) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(_snap(1, hist: [_cc('Foo', inst: 5, bytes: 100)]))
        ..debugAdd(_snap(2, hist: [_cc('Foo', inst: 15, bytes: 300)]));
      c.toggleSelection(1);
      c.toggleSelection(2);
      await tester.pumpWidget(_wrapDesktop(SnapshotsView(controller: c)));
      await tester.pump();
      expect(find.text('Foo'), findsWidgets);
      expect(find.textContaining('Δ'), findsWidgets);
    });

    testWidgets('a single selected snapshot renders the show-all table', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(_snap(1, hist: [_cc('Foo', inst: 5, bytes: 100)]));
      c.toggleSelection(1);
      await tester.pumpWidget(_wrapDesktop(SnapshotsView(controller: c)));
      await tester.pump();
      expect(find.text('Foo'), findsWidgets);
      expect(find.textContaining('no baseline'), findsOneWidget);
    });
  });

  group('ClassHistogramView', () {
    testWidgets('no snapshot shows empty state', (tester) async {
      await tester.pumpWidget(
        _wrap(ClassHistogramView(controller: _controller())),
      );
      expect(find.textContaining('No snapshot captured yet'), findsOneWidget);
    });

    testWidgets('renders rows and filter narrows them', (tester) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(
          _snap(1, hist: [_cc('Alpha', inst: 3), _cc('Beta', inst: 7)]),
        );
      await tester.pumpWidget(_wrapDesktop(ClassHistogramView(controller: c)));
      await tester.pump();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pump();
      // The Beta row is filtered out. (find.text also matches the filter
      // field's own EditableText, so assert Alpha with findsWidgets.)
      expect(find.text('Beta'), findsNothing);
      expect(find.text('Alpha'), findsWidgets);
    });

    testWidgets('tapping a class shows its root grouping in the detail panel', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(
          _snap(
            1,
            hist: [_cc('Foo', inst: 3)],
            profiles: [
              _profile('Foo', {RootKind.stream: 2, RootKind.liveTree: 1}),
            ],
          ),
        );
      await tester.pumpWidget(_wrapDesktop(ClassHistogramView(controller: c)));
      await tester.pump();

      await tester.tap(find.text('Foo'));
      await tester.pump();
      expect(find.text('Retained by (closest root)'), findsOneWidget);
    });

    testWidgets('class detail shows the per-path distribution and expands it', (
      tester,
    ) async {
      _setDesktopSize(tester);
      const path = GraphRetainingPath(
        hops: [
          GraphHop(className: 'ProviderNode'),
          GraphHop(className: 'Listener', field: '_l'),
        ],
        rootKind: RootKind.other,
      );
      final c = _controller()
        ..debugAdd(
          _snap(
            1,
            hist: [_cc('Listener', inst: 3)],
            profiles: [
              _profile('Listener', {RootKind.other: 3}, path: path),
            ],
            distributions: [
              const ClassPathDistribution(
                className: 'Listener',
                totalInstances: 3,
                sampledInstances: 3,
                paths: [
                  PathBucket(path: path, instanceCount: 2, shallowBytes: 20),
                ],
                otherPathCount: 1,
              ),
            ],
          ),
        );
      await tester.pumpWidget(_wrapDesktop(ClassHistogramView(controller: c)));
      await tester.pump();

      await tester.tap(find.text('Listener'));
      await tester.pump();
      expect(find.text('Retaining paths'), findsOneWidget);
      expect(find.textContaining('in more paths'), findsOneWidget);

      // Row expands on tap to reveal the full hop-by-hop path.
      await tester.tap(find.text('ProviderNode → Listener'));
      await tester.pump();
      expect(find.byType(RetainingPathTile), findsOneWidget);
    });
  });

  group('RetainingPathsView', () {
    testWidgets('no snapshot shows empty state', (tester) async {
      await tester.pumpWidget(
        _wrap(RetainingPathsView(controller: _controller())),
      );
      expect(
        find.textContaining('Capture a snapshot to explore retaining paths'),
        findsOneWidget,
      );
    });

    testWidgets('groups profiles by root bucket and shows a path on select', (
      tester,
    ) async {
      _setDesktopSize(tester);
      const path = GraphRetainingPath(
        hops: [
          GraphHop(className: 'StreamController'),
          GraphHop(className: 'Leaky', field: '_sub'),
        ],
        rootKind: RootKind.stream,
      );
      final c = _controller()
        ..debugAdd(
          _snap(
            1,
            profiles: [
              _profile('Leaky', {RootKind.stream: 5}, path: path),
              _profile('MyWidget', {RootKind.liveTree: 10}),
            ],
          ),
        );
      await tester.pumpWidget(_wrapDesktop(RetainingPathsView(controller: c)));
      await tester.pump();

      expect(find.text('LEAK-PRONE ROOTS'), findsOneWidget);
      expect(find.text('LIVE TREE'), findsOneWidget);
      expect(find.text('Leaky'), findsWidgets);

      await tester.tap(find.text('Leaky').first);
      await tester.pump();
      expect(find.text('Representative retaining path'), findsOneWidget);
      expect(find.textContaining('StreamController'), findsOneWidget);
    });
  });
}
