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

SnapshotBundle _bundle(
  String label, {
  required DateTime capturedAt,
  List<ClassCount> histogram = const [],
  List<GraphLeakCluster> clusters = const [],
}) => SnapshotBundle(
  capturedAt: capturedAt,
  label: label,
  histogram: histogram,
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
    resolvedAppPackages: const ['my_app'],
  ),
);

ClassCount _count(String name, int instances) => ClassCount(
  className: name,
  libraryUri: Uri.parse('package:my_app/x.dart'),
  instanceCount: instances,
  shallowBytes: instances * 10,
);

void main() {
  testWidgets('compare rows render a chip wired from the workspace triage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final workspace = WorkspaceController();
    // A → B growth of LeakyThing; B headlines a LeakyThing cluster (sigA). B is
    // captured later so it resolves as the comparison ("after") snapshot.
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
      ),
      source: DumpSource.file,
    );
    // sigA is KNOWN from a prior session.
    workspace.updateTriage(
      TriageStore.empty.upsert(
        TriageEntry(
          signature: 'sigA',
          firstSeen: DateTime(2026, 6, 1),
          status: TriageStatus.known,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Theme(
          data: radarDarkTheme(),
          child: Scaffold(body: CompareScreen(workspace: workspace)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LeakyThing'), findsOneWidget);
    expect(find.text('KNOWN'), findsOneWidget);
  });
}
