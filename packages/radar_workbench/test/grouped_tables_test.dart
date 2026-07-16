import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

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

double _dy(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

ClassCountDiff _diff(String name, {required String lib, int afterBytes = 0}) =>
    ClassCountDiff(
      before: ClassCount(
        className: name,
        libraryUri: Uri.parse(lib),
        instanceCount: 0,
        shallowBytes: 0,
      ),
      after: ClassCount(
        className: name,
        libraryUri: Uri.parse(lib),
        instanceCount: 1,
        shallowBytes: afterBytes,
      ),
    );

// Project (declared) + celebrated case (sdk-declared, app-anchored) + a
// dependency + a framework row.
List<ClassCountDiff> _diffs() => [
  _diff('ProjectLeak', lib: 'package:my_app/p.dart', afterBytes: 500),
  _diff('LeakySub', lib: 'dart:async', afterBytes: 250),
  _diff('DepLeak', lib: 'package:livekit/d.dart', afterBytes: 300),
  _diff('FrameworkLeak', lib: 'package:flutter/f.dart', afterBytes: 100),
];

Map<String, Uri?> _anchors() => {
  'LeakySub': Uri.parse('package:my_app/screen.dart'),
};

Widget _diffTable({
  List<ClassCountDiff>? diffs,
  Map<String, Uri?>? anchors,
  Set<String> projectPackages = const {'my_app'},
}) => DiffTable(
  diffs: diffs ?? _diffs(),
  summary: const SizedBox.shrink(),
  selected: null,
  onSelected: (_) {},
  classAnchors: anchors ?? _anchors(),
  projectPackages: projectPackages,
);

GraphAnalysisResult _analysis({
  List<String> appPackages = const ['my_app'],
  List<GraphLeakCluster> clusters = const [],
}) => GraphAnalysisResult(
  clusters: clusters,
  stats: const GraphAnalysisStats(
    totalObjects: 0,
    reachableObjects: 0,
    leakCandidates: 0,
    clusters: 0,
    suppressedByAppFilter: 0,
    warnings: [],
  ),
  resolvedAppPackages: appPackages,
);

GraphLeakCluster _anchoredCluster(String name, {required Uri anchorLib}) =>
    GraphLeakCluster(
      className: name,
      libraryUri: Uri.parse('dart:async'),
      instanceCount: 1,
      retainedShallowBytes: 100,
      representativePath: GraphRetainingPath(
        hops: [
          GraphHop(className: 'Owner', libraryUri: anchorLib),
          GraphHop(className: name, libraryUri: Uri.parse('dart:async')),
        ],
        rootKind: RootKind.timer,
      ),
      rootKind: RootKind.timer,
      confidence: LeakConfidence.confirmed,
      signature: 'sig-$name',
      anchorHopIndex: 0,
    );

ClassCount _cc(String name, String lib, int bytes) => ClassCount(
  className: name,
  libraryUri: Uri.parse(lib),
  instanceCount: 1,
  shallowBytes: bytes,
);

SnapshotBundle _histSnap({
  List<ClassCount>? histogram,
  List<GraphLeakCluster> clusters = const [],
  List<String> appPackages = const ['my_app'],
  int id = 1,
  int second = 1,
}) => SnapshotBundle(
  id: id,
  capturedAt: DateTime(2026, 1, 1, 12, 0, second),
  label: 'Snapshot $id',
  histogram:
      histogram ??
      [
        _cc('MyLeak', 'package:my_app/m.dart', 400),
        _cc('DepThing', 'package:livekit/t.dart', 200),
      ],
  analysisResult: _analysis(appPackages: appPackages, clusters: clusters),
);

MemoryController _controller(SnapshotBundle bundle) => MemoryController(
  snapshotSource: FakeSnapshotSource(),
  connection: FakeRadarConnection(),
)..debugAdd(bundle);

void main() {
  group('DiffTable grouped default', () {
    testWidgets('project pinned first + expanded; deps/runtime present but '
        'collapsed, in order', (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrapDesktop(_diffTable()));
      await tester.pump();

      // Project group is anchored (celebrated case) → "retained via"; expanded.
      expect(find.text('retained via my_app'), findsOneWidget);
      expect(find.text('ProjectLeak'), findsOneWidget);
      expect(find.text('LeakySub'), findsOneWidget);

      // Dependency + runtime are declared-fallback only → "declared in";
      // collapsed (rows hidden).
      expect(find.text('declared in livekit'), findsOneWidget);
      expect(find.text('DepLeak'), findsNothing);
      expect(find.text('declared in (runtime)'), findsOneWidget);
      expect(find.text('FrameworkLeak'), findsNothing);

      // On-screen order: project above dependency above runtime.
      final project = _dy(tester, find.text('retained via my_app'));
      final dep = _dy(tester, find.text('declared in livekit'));
      final runtime = _dy(tester, find.text('declared in (runtime)'));
      expect(project, lessThan(dep));
      expect(dep, lessThan(runtime));
    });

    testWidgets('collapsed group headers show the rollup Δbytes', (
      tester,
    ) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrapDesktop(_diffTable()));
      await tester.pump();

      // livekit dependency group is collapsed; its header shows +300 B.
      expect(find.text('+300 B'), findsWidgets);
    });

    testWidgets('expanding a collapsed group reveals its rows', (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrapDesktop(_diffTable()));
      await tester.pump();

      expect(find.text('DepLeak'), findsNothing);
      await tester.tap(find.text('declared in livekit'));
      await tester.pump();
      expect(find.text('DepLeak'), findsOneWidget);
    });

    testWidgets('toggling to flat shows every row in sort order', (
      tester,
    ) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrapDesktop(_diffTable()));
      await tester.pump();

      await tester.tap(find.text('flat'));
      await tester.pump();

      // No group headers in flat mode.
      expect(find.textContaining('retained via'), findsNothing);
      expect(find.textContaining('declared in'), findsNothing);

      // Every row present, ordered by Δbytes desc (500 > 300 > 250 > 100).
      final project = _dy(tester, find.text('ProjectLeak'));
      final dep = _dy(tester, find.text('DepLeak'));
      final sub = _dy(tester, find.text('LeakySub'));
      final framework = _dy(tester, find.text('FrameworkLeak'));
      expect(project, lessThan(dep));
      expect(dep, lessThan(sub));
      expect(sub, lessThan(framework));
    });

    testWidgets('hide-framework preset drops runtime but keeps the '
        'app-anchored sdk row', (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrapDesktop(_diffTable()));
      await tester.pump();

      expect(find.text('declared in (runtime)'), findsOneWidget);
      await tester.tap(find.text('hide framework'));
      await tester.pump();

      // Runtime group + framework row gone.
      expect(find.text('declared in (runtime)'), findsNothing);
      expect(find.text('FrameworkLeak'), findsNothing);
      // Celebrated case survives: dart:async declared but app-anchored.
      expect(find.text('retained via my_app'), findsOneWidget);
      expect(find.text('LeakySub'), findsOneWidget);
    });
  });

  group('DiffTable degenerate (no project group) honesty', () {
    testWidgets('resolved but no project rows → positive banner, all '
        'expanded', (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(
        _wrapDesktop(
          _diffTable(
            diffs: [
              _diff('DepLeak', lib: 'package:livekit/d.dart', afterBytes: 300),
              _diff(
                'FrameworkLeak',
                lib: 'package:flutter/f.dart',
                afterBytes: 100,
              ),
            ],
            anchors: const {},
            projectPackages: const {'my_app'},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('No project-attributed leaks in this diff.'),
        findsOneWidget,
      );
      // All-expanded fallback: every group's rows are visible.
      expect(find.text('DepLeak'), findsOneWidget);
      expect(find.text('FrameworkLeak'), findsOneWidget);
    });

    testWidgets('unresolved project set → warning banner', (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(
        _wrapDesktop(
          _diffTable(
            diffs: [
              _diff('DepLeak', lib: 'package:livekit/d.dart', afterBytes: 300),
            ],
            anchors: const {},
            projectPackages: const {},
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Attribution unavailable'), findsOneWidget);
    });
  });

  group('ClassHistogramView grouped', () {
    testWidgets('rows show an origin chip and package label', (tester) async {
      _setDesktopSize(tester);
      final c = _controller(_histSnap());
      await tester.pumpWidget(_wrapDesktop(ClassHistogramView(controller: c)));
      await tester.pump();

      await tester.tap(find.text('flat'));
      await tester.pump();

      expect(find.byType(OriginChip), findsWidgets);
      expect(find.text('MyLeak'), findsOneWidget);
      expect(find.textContaining('my_app'), findsWidgets);
    });

    testWidgets('row chip uses EFFECTIVE origin (anchor) in flat mode', (
      tester,
    ) async {
      _setDesktopSize(tester);
      // LeakySub declared dart:async but anchored to my_app via a cluster.
      final snap = _histSnap(
        histogram: [
          _cc('LeakySub', 'dart:async', 250),
          _cc('DepThing', 'package:livekit/t.dart', 200),
        ],
        clusters: [
          _anchoredCluster(
            'LeakySub',
            anchorLib: Uri.parse('package:my_app/screen.dart'),
          ),
        ],
      );
      await tester.pumpWidget(
        _wrapDesktop(ClassHistogramView(controller: _controller(snap))),
      );
      await tester.pump();
      await tester.tap(find.text('flat'));
      await tester.pump();

      // Exactly one YOURS chip — the app-anchored dart:async row (not the
      // declared-sdk chip it would show without the effective-origin rule).
      expect(find.text('YOURS'), findsOneWidget);
      expect(find.text('LeakySub'), findsOneWidget);
    });

    testWidgets('defaults to grouped with a project group header', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final c = _controller(_histSnap());
      await tester.pumpWidget(_wrapDesktop(ClassHistogramView(controller: c)));
      await tester.pump();

      // MyLeak declared my_app (no anchor) → "declared in my_app".
      expect(find.text('declared in my_app'), findsOneWidget);
      expect(find.text('MyLeak'), findsOneWidget);
    });
  });

  group('DiffTable state resets across diff-pair changes', () {
    testWidgets('collapsing a group does not persist to the next pair', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final c =
          MemoryController(
              snapshotSource: FakeSnapshotSource(),
              connection: FakeRadarConnection(),
            )
            ..debugAdd(
              _histSnap(
                id: 1,
                second: 1,
                histogram: [_cc('ProjectLeak', 'package:my_app/p.dart', 100)],
              ),
            )
            ..debugAdd(
              _histSnap(
                id: 2,
                second: 2,
                histogram: [_cc('ProjectLeak', 'package:my_app/p.dart', 300)],
              ),
            )
            ..debugAdd(
              _histSnap(
                id: 3,
                second: 3,
                histogram: [_cc('ProjectLeak', 'package:my_app/p.dart', 500)],
              ),
            );
      c.toggleSelection(1);
      c.toggleSelection(2);

      await tester.pumpWidget(
        _wrapDesktop(SnapshotsView(controller: c, onExport: (_) async {})),
      );
      await tester.pump();

      // Project group expanded by default → row visible.
      expect(find.text('ProjectLeak'), findsOneWidget);
      // Collapse it.
      await tester.tap(find.text('declared in my_app'));
      await tester.pump();
      expect(find.text('ProjectLeak'), findsNothing);

      // Switch the diff pair (drops snapshot 1 → pair becomes 2+3).
      c.toggleSelection(3);
      await tester.pump();

      // Fresh pair identity → state reset → project group expanded again.
      expect(find.text('ProjectLeak'), findsOneWidget);
    });
  });
}
