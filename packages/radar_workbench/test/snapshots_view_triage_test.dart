import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

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

GraphLeakCluster _cluster(String className, String signature) =>
    GraphLeakCluster(
      className: className,
      libraryUri: Uri.parse('package:my_app/x.dart'),
      instanceCount: 2,
      retainedShallowBytes: 100,
      representativePath: const GraphRetainingPath(
        hops: [GraphHop(className: 'OwnerState', field: '_sub')],
        rootKind: RootKind.stream,
      ),
      rootKind: RootKind.stream,
      confidence: LeakConfidence.heuristic,
      signature: signature,
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
    clusters: [_cluster('LeakyThing', 'sigA')],
    stats: const GraphAnalysisStats(
      totalObjects: 0,
      reachableObjects: 0,
      leakCandidates: 0,
      clusters: 1,
      suppressedByAppFilter: 0,
      warnings: [],
    ),
    resolvedAppPackages: const ['my_app'],
  ),
);

void main() {
  testWidgets('diff rows render a cross-session chip wired from the triage '
      'store', (tester) async {
    _setDesktopSize(tester);
    final memory = MemoryController(
      snapshotSource: FakeSnapshotSource(),
      connection: FakeRadarConnection(),
    );
    memory.addBundle(_snap()); // auto-selected → absolute diff shows all rows

    final triage = TriageStore.empty.upsert(
      TriageEntry(
        signature: 'sigA',
        firstSeen: DateTime(2026, 6, 1),
        status: TriageStatus.known,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        SnapshotsView(
          controller: memory,
          onExport: (_) async {},
          triage: triage,
        ),
      ),
    );
    await tester.pump();

    // The LeakyThing row shows its class NEW/KNOWN chip — here KNOWN.
    expect(find.text('LeakyThing'), findsOneWidget);
    expect(find.text('KNOWN'), findsOneWidget);
  });
}
