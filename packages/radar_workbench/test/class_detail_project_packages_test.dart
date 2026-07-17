import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

// Every ClassDetailPanel call site (histogram, DevTools diff, desktop compare)
// must pass the analysis-resolved project set so the inspector's retaining-path
// hop chips classify origin identically to the adjacent row chips (#12).

Widget _wrap(Widget child) => MaterialApp(
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

ClassRootProfile _profile(String className) => ClassRootProfile(
  className: className,
  libraryUri: Uri.parse('package:my_app/x.dart'),
  byRoot: const {RootKind.stream: 2},
  totalInstances: 2,
  retainedShallowBytes: 100,
  representativePath: GraphRetainingPath(
    hops: [
      GraphHop(
        className: 'OwnerState',
        field: '_sub',
        libraryUri: Uri.parse('package:my_app/x.dart'),
      ),
    ],
    rootKind: RootKind.stream,
  ),
);

SnapshotBundle _snap() => SnapshotBundle(
  id: 1,
  capturedAt: DateTime(2026, 1, 1, 12),
  label: 'Snapshot 1',
  histogram: [
    ClassCount(
      className: 'LeakyThing',
      libraryUri: Uri.parse('package:my_app/x.dart'),
      instanceCount: 2,
      shallowBytes: 100,
    ),
  ],
  analysisResult: GraphAnalysisResult(
    clusters: const [],
    classRootProfiles: [_profile('LeakyThing')],
    stats: const GraphAnalysisStats(
      totalObjects: 0,
      reachableObjects: 0,
      leakCandidates: 0,
      clusters: 0,
      suppressedByAppFilter: 0,
      warnings: [],
    ),
    resolvedAppPackages: const ['my_app'],
  ),
);

MemoryController _memoryWithSnapshot() {
  final memory = MemoryController(
    snapshotSource: FakeSnapshotSource(),
    connection: FakeRadarConnection(),
  );
  memory.addBundle(_snap());
  return memory;
}

void main() {
  testWidgets('histogram wires project packages into the ClassDetailPanel', (
    tester,
  ) async {
    _setDesktopSize(tester);
    final memory = _memoryWithSnapshot();

    await tester.pumpWidget(_wrap(ClassHistogramView(controller: memory)));
    await tester.pump();

    final panel = tester.widget<ClassDetailPanel>(
      find.byType(ClassDetailPanel),
    );
    expect(panel.projectPackages, contains('my_app'));
  });

  testWidgets(
    'DevTools diff wires project packages into the ClassDetailPanel',
    (tester) async {
      _setDesktopSize(tester);
      final memory = _memoryWithSnapshot();

      await tester.pumpWidget(
        _wrap(
          SnapshotsView(
            controller: memory,
            onExport: (_) async {},
            triage: TriageStore.empty,
          ),
        ),
      );
      await tester.pump();

      final panel = tester.widget<ClassDetailPanel>(
        find.byType(ClassDetailPanel),
      );
      expect(panel.projectPackages, contains('my_app'));
    },
  );
}
