import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

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

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('ConnectionBar', () {
    testWidgets('shows disconnected chip when not connected', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 44,
            child: ConnectionBar(connection: FakeRadarConnection()),
          ),
        ),
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

  group('SnapshotsView', () {
    testWidgets('no snapshots shows the idle capture hint', (tester) async {
      await tester.pumpWidget(
        _wrap(SnapshotsView(controller: _controller(), onExport: (_) {})),
      );
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
      await tester.pumpWidget(
        _wrapDesktop(SnapshotsView(controller: c, onExport: (_) {})),
      );
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
      await tester.pumpWidget(
        _wrapDesktop(SnapshotsView(controller: c, onExport: (_) {})),
      );
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
