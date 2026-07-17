import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

// Reproduces the desktop 800x600 RenderFlex overflow and pins the histogram +
// diff layouts as width-safe down to the smallest host width (desktop min
// window 920, minus nav rail + detail panel → a ~380px content column).

GraphAnalysisResult _analysis() => const GraphAnalysisResult(
  clusters: [],
  stats: GraphAnalysisStats(
    totalObjects: 0,
    reachableObjects: 0,
    leakCandidates: 0,
    clusters: 0,
    suppressedByAppFilter: 0,
    warnings: [],
  ),
  resolvedAppPackages: ['my_app'],
);

SnapshotBundle _snap() => SnapshotBundle(
  id: 1,
  capturedAt: DateTime(2026),
  label: 's',
  histogram: [
    ClassCount(
      className: 'SomeVeryLongLeakyClassName',
      libraryUri: Uri.parse('package:livekit_client/subscription.dart'),
      instanceCount: 3,
      shallowBytes: 400,
    ),
    ClassCount(
      className: 'Another',
      libraryUri: Uri.parse('package:my_app/m.dart'),
      instanceCount: 2,
      shallowBytes: 200,
    ),
  ],
  analysisResult: _analysis(),
);

MemoryController _controller() => MemoryController(
  snapshotSource: FakeSnapshotSource(),
  connection: FakeRadarConnection(),
)..debugAdd(_snap());

GraphLeakCluster _cluster() => GraphLeakCluster(
  className: 'SomeVeryLongLeakyOwnerStateClassName',
  libraryUri: Uri.parse('dart:async'),
  instanceCount: 12,
  retainedShallowBytes: 400000,
  representativePath: GraphRetainingPath(
    hops: [
      GraphHop(
        className: 'SomeVeryLongLeakyOwnerStateClassName',
        field: '_subscriptionWithAVeryLongFieldName',
        libraryUri: Uri.parse('package:my_app/screens/leaky_screen.dart'),
      ),
      const GraphHop(className: 'StreamSubscription'),
    ],
    rootKind: RootKind.stream,
  ),
  rootKind: RootKind.stream,
  confidence: LeakConfidence.confirmed,
  signature: 'sig-1',
  leafClassName: 'StreamSubscription',
  anchorHopIndex: 0,
);

MemoryController _clustersController() =>
    MemoryController(
      snapshotSource: FakeSnapshotSource(),
      connection: FakeRadarConnection(),
    )..debugAdd(
      SnapshotBundle(
        id: 1,
        capturedAt: DateTime(2026),
        label: 's',
        histogram: const [],
        analysisResult: GraphAnalysisResult(
          clusters: [_cluster()],
          stats: const GraphAnalysisStats(
            totalObjects: 0,
            reachableObjects: 0,
            leakCandidates: 0,
            clusters: 1,
            suppressedByAppFilter: 0,
            warnings: ['heap capture truncated at 500k objects'],
          ),
          resolvedAppPackages: const ['my_app'],
        ),
      ),
    );

Widget _wrap(Widget child, Size size) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    theme: radarDarkTheme(),
    home: Scaffold(
      body: SizedBox.fromSize(size: size, child: child),
    ),
  ),
);

Future<void> _pumpAt(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(_wrap(child, size));
  await tester.pump();
}

void main() {
  // 800x600 is the default flutter_test viewport that broke radar_desktop.
  // 722x600 simulates the desktop min (920) minus a ~198 nav rail (content
  // column ≈ 381 once the 340 detail panel is subtracted).
  const sizes = [Size(800, 600), Size(722, 600), Size(1280, 800)];

  for (final size in sizes) {
    testWidgets('ClassHistogramView has no overflow at ${size.width}px', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        ClassHistogramView(controller: _controller()),
        size,
      );
      expect(tester.takeException(), isNull);
      // Toggle to flat then grouped to exercise both list layouts.
      await tester.tap(find.text('flat'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in sizes) {
    testWidgets('LeakClustersView has no overflow at ${size.width}px', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        LeakClustersView(controller: _clustersController()),
        size,
      );
      expect(tester.takeException(), isNull);
      // Expanding a row exercises the warnings strip + path tile + meta-line
      // layout at the narrowest widths.
      await tester.tap(find.text('SomeVeryLongLeakyOwnerStateClassName'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in sizes) {
    testWidgets('DiffTable has no overflow at ${size.width}px', (tester) async {
      await _pumpAt(
        tester,
        DiffTable(
          diffs: [
            ClassCountDiff(
              before: ClassCount(
                className: 'ProjectLeak',
                libraryUri: Uri.parse('package:my_app/p.dart'),
                instanceCount: 0,
                shallowBytes: 0,
              ),
              after: ClassCount(
                className: 'ProjectLeak',
                libraryUri: Uri.parse('package:my_app/p.dart'),
                instanceCount: 3,
                shallowBytes: 500,
              ),
            ),
          ],
          summary: const Text('12.3 KB → 45.6 KB (+33.3 KB across 8 classes)'),
          selected: null,
          onSelected: (_) {},
          projectPackages: const {'my_app'},
        ),
        size,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
