import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_desktop/src/screens/compare_screen.dart';
import 'package:radar_desktop/src/workspace/workspace_controller.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

GraphLeakCluster _cluster(String signature, String className) =>
    GraphLeakCluster(
      className: className,
      libraryUri: Uri.parse('package:my_app/x.dart'),
      instanceCount: 5,
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
      rootKind: RootKind.stream,
      confidence: LeakConfidence.heuristic,
      signature: signature,
      anchorHopIndex: 0,
    );

ClassRootProfile _profile(String className) => ClassRootProfile(
  className: className,
  libraryUri: Uri.parse('package:my_app/x.dart'),
  byRoot: const {RootKind.stream: 5},
  totalInstances: 5,
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

SnapshotBundle _bundle(
  String label, {
  required DateTime capturedAt,
  required List<ClassCount> histogram,
  List<GraphLeakCluster> clusters = const [],
  List<ClassRootProfile> profiles = const [],
}) => SnapshotBundle(
  capturedAt: capturedAt,
  label: label,
  histogram: histogram,
  analysisResult: GraphAnalysisResult(
    clusters: clusters,
    classRootProfiles: profiles,
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

ClassCount _count(String name, int instances) => ClassCount(
  className: name,
  libraryUri: Uri.parse('package:my_app/x.dart'),
  instanceCount: instances,
  shallowBytes: instances * 10,
);

WorkspaceController _twoDumpWorkspace() {
  final workspace = WorkspaceController();
  workspace.addExisting(
    _bundle(
      'A',
      capturedAt: DateTime(2026, 1, 1),
      histogram: [_count('LeakyThing', 1)],
    ),
    source: DumpSource.file,
  );
  workspace.addExisting(
    _bundle(
      'B',
      capturedAt: DateTime(2026, 1, 2),
      histogram: [_count('LeakyThing', 5)],
      clusters: [_cluster('sigA', 'LeakyThing')],
      profiles: [_profile('LeakyThing')],
    ),
    source: DumpSource.file,
  );
  return workspace;
}

Widget _host(Widget child) => MaterialApp(
  home: Theme(
    data: radarDarkTheme(),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'desktop Compare wires anchors + project packages into DiffTable (#11)',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final workspace = _twoDumpWorkspace();
      await tester.pumpWidget(_host(CompareScreen(workspace: workspace)));
      await tester.pumpAndSettle();

      final table = tester.widget<DiffTable>(find.byType(DiffTable));
      // The S1 "which are MINE" grouping needs the resolved project set…
      expect(table.projectPackages, contains('my_app'));
      // …and the anchor map so class rows pin under their owner package.
      expect(table.classAnchors, isNotEmpty);
    },
  );

  testWidgets(
    'desktop Compare wires project packages into the ClassDetailPanel (#12)',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final workspace = _twoDumpWorkspace();
      await tester.pumpWidget(_host(CompareScreen(workspace: workspace)));
      await tester.pumpAndSettle();

      // The inspector's hop chips classify origin from projectPackages — so
      // they must agree with the row chips rather than say DEPENDENCY.
      final panel = tester.widget<ClassDetailPanel>(
        find.byType(ClassDetailPanel),
      );
      expect(panel.projectPackages, contains('my_app'));
    },
  );
}
