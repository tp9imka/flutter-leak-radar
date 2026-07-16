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

ClassCountDiff _diff(
  String name, {
  required String lib,
  int afterInst = 1,
  int afterBytes = 0,
}) => ClassCountDiff(
  before: ClassCount(
    className: name,
    libraryUri: Uri.parse(lib),
    instanceCount: 0,
    shallowBytes: 0,
  ),
  after: ClassCount(
    className: name,
    libraryUri: Uri.parse(lib),
    instanceCount: afterInst,
    shallowBytes: afterBytes,
  ),
);

List<ClassCountDiff> _diffs() => [
  _diff('ProjectLeak', lib: 'package:my_app/p.dart', afterBytes: 500),
  _diff('DepLeak', lib: 'package:livekit/d.dart', afterBytes: 300),
  _diff('FrameworkLeak', lib: 'package:flutter/f.dart', afterBytes: 100),
];

Widget _diffTable() => DiffTable(
  diffs: _diffs(),
  summary: const SizedBox.shrink(),
  selected: null,
  onSelected: (_) {},
  projectPackages: const {'my_app'},
);

GraphAnalysisResult _analysis({List<String> appPackages = const ['my_app']}) =>
    GraphAnalysisResult(
      clusters: const [],
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

SnapshotBundle _histSnap() => SnapshotBundle(
  id: 1,
  capturedAt: DateTime(2026, 1, 1, 12),
  label: 'Snapshot 1',
  histogram: [
    ClassCount(
      className: 'MyLeak',
      libraryUri: Uri.parse('package:my_app/m.dart'),
      instanceCount: 4,
      shallowBytes: 400,
    ),
    ClassCount(
      className: 'DepThing',
      libraryUri: Uri.parse('package:livekit/t.dart'),
      instanceCount: 2,
      shallowBytes: 200,
    ),
  ],
  analysisResult: _analysis(),
);

MemoryController _controller(SnapshotBundle bundle) => MemoryController(
  snapshotSource: FakeSnapshotSource(),
  connection: FakeRadarConnection(),
)..debugAdd(bundle);

void main() {
  group('DiffTable grouped default', () {
    testWidgets('project group pinned first + expanded; runtime present but '
        'collapsed', (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrapDesktop(_diffTable()));
      await tester.pump();

      // Project group header + its row are visible (expanded).
      expect(find.textContaining('retained via my_app'), findsWidgets);
      expect(find.text('ProjectLeak'), findsOneWidget);

      // Dependency group present but collapsed (row hidden).
      expect(find.textContaining('retained via livekit'), findsWidgets);
      expect(find.text('DepLeak'), findsNothing);

      // Runtime group present but collapsed.
      expect(find.textContaining('retained via runtime'), findsWidgets);
      expect(find.text('FrameworkLeak'), findsNothing);
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
      await tester.tap(find.textContaining('retained via livekit'));
      await tester.pump();
      expect(find.text('DepLeak'), findsOneWidget);
    });

    testWidgets('toggling to flat shows every row', (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrapDesktop(_diffTable()));
      await tester.pump();

      await tester.tap(find.text('flat'));
      await tester.pump();

      expect(find.text('ProjectLeak'), findsOneWidget);
      expect(find.text('DepLeak'), findsOneWidget);
      expect(find.text('FrameworkLeak'), findsOneWidget);
      // No group headers in flat mode.
      expect(find.textContaining('retained via'), findsNothing);
    });

    testWidgets('hide-framework preset chip drops the runtime group', (
      tester,
    ) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrapDesktop(_diffTable()));
      await tester.pump();

      expect(find.textContaining('retained via runtime'), findsWidgets);
      await tester.tap(find.text('hide framework'));
      await tester.pump();

      expect(find.textContaining('retained via runtime'), findsNothing);
      expect(find.text('FrameworkLeak'), findsNothing);
      // Project + dependency groups remain.
      expect(find.textContaining('retained via my_app'), findsWidgets);
    });
  });

  group('ClassHistogramView grouped', () {
    testWidgets('rows show an origin chip and package label', (tester) async {
      _setDesktopSize(tester);
      final c = _controller(_histSnap());
      await tester.pumpWidget(_wrapDesktop(ClassHistogramView(controller: c)));
      await tester.pump();

      // Switch to flat so chips come from rows, not group headers.
      await tester.tap(find.text('flat'));
      await tester.pump();

      expect(find.byType(OriginChip), findsWidgets);
      expect(find.text('MyLeak'), findsOneWidget);
      // The row's package label is shown (no library column exists).
      expect(find.textContaining('my_app'), findsWidgets);
    });

    testWidgets('defaults to grouped with a project group header', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final c = _controller(_histSnap());
      await tester.pumpWidget(_wrapDesktop(ClassHistogramView(controller: c)));
      await tester.pump();

      expect(find.textContaining('retained via my_app'), findsWidgets);
      expect(find.text('MyLeak'), findsOneWidget);
    });
  });
}
