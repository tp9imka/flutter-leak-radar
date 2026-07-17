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

GraphRetainingPath _path({Uri? anchorLib, String owner = 'OwnerState'}) =>
    GraphRetainingPath(
      hops: [
        GraphHop(className: owner, field: '_sub', libraryUri: anchorLib),
        const GraphHop(className: 'StreamSubscription'),
      ],
      rootKind: RootKind.stream,
    );

GraphLeakCluster _cluster({
  String className = 'StreamSubscription',
  LeakConfidence confidence = LeakConfidence.confirmed,
  int instances = 2,
  int bytes = 100,
  String signature = 'sig',
  Uri? libraryUri,
  int? anchorHopIndex,
  Uri? anchorLib,
  String? leafClassName,
  RootKind rootKind = RootKind.stream,
}) => GraphLeakCluster(
  className: className,
  libraryUri: libraryUri,
  instanceCount: instances,
  retainedShallowBytes: bytes,
  representativePath: _path(anchorLib: anchorLib),
  rootKind: rootKind,
  confidence: confidence,
  signature: signature,
  leafClassName: leafClassName,
  anchorHopIndex: anchorHopIndex,
);

SnapshotBundle _snap({
  List<GraphLeakCluster> clusters = const [],
  List<String> warnings = const [],
  int suppressedByAppFilter = 0,
  int suppressedByLiveTree = 0,
  List<String> appPackages = const ['my_app'],
}) => SnapshotBundle(
  id: 1,
  capturedAt: DateTime(2026, 1, 1, 12),
  label: 'Snapshot 1',
  histogram: const [],
  analysisResult: GraphAnalysisResult(
    clusters: clusters,
    stats: GraphAnalysisStats(
      totalObjects: 0,
      reachableObjects: 0,
      leakCandidates: 0,
      clusters: clusters.length,
      suppressedByAppFilter: suppressedByAppFilter,
      suppressedByLiveTree: suppressedByLiveTree,
      warnings: warnings,
    ),
    resolvedAppPackages: appPackages,
  ),
);

const _projectPackages = {'my_app'};
final _projectLib = Uri.parse('package:my_app/screen.dart');
final _dependencyLib = Uri.parse('package:livekit_client/x.dart');

void main() {
  group('rankLeakClusters', () {
    test(
      'orders confirmed before heuristic even when heuristic weighs more',
      () {
        final confirmed = _cluster(
          signature: 'a',
          confidence: LeakConfidence.confirmed,
          bytes: 10,
          instances: 1,
        );
        final heuristic = _cluster(
          signature: 'b',
          confidence: LeakConfidence.heuristic,
          bytes: 1000,
          instances: 100,
        );
        final ranked = rankLeakClusters([
          heuristic,
          confirmed,
        ], projectPackages: _projectPackages);
        expect(ranked.map((c) => c.signature), ['a', 'b']);
      },
    );

    test('orders project-anchored before non-project at equal confidence '
        'even when the non-project cluster weighs more', () {
      final project = _cluster(
        signature: 'a',
        libraryUri: Uri.parse('dart:async'),
        anchorHopIndex: 0,
        anchorLib: _projectLib,
        bytes: 10,
        instances: 1,
      );
      final dependency = _cluster(
        signature: 'b',
        libraryUri: _dependencyLib,
        bytes: 1000,
        instances: 100,
      );
      final ranked = rankLeakClusters([
        dependency,
        project,
      ], projectPackages: _projectPackages);
      expect(ranked.map((c) => c.signature), ['a', 'b']);
    });

    test('orders by shallowBytes × instances desc within a tier', () {
      final small = _cluster(signature: 'a', bytes: 100, instances: 2);
      final big = _cluster(signature: 'b', bytes: 100, instances: 50);
      final ranked = rankLeakClusters([
        small,
        big,
      ], projectPackages: _projectPackages);
      expect(ranked.map((c) => c.signature), ['b', 'a']);
    });

    test('breaks exact ties deterministically by signature asc', () {
      final z = _cluster(signature: 'zzz', bytes: 100, instances: 2);
      final a = _cluster(signature: 'aaa', bytes: 100, instances: 2);
      // Same confidence, origin, and weight — only the signature differs.
      final ranked = rankLeakClusters([
        z,
        a,
      ], projectPackages: _projectPackages);
      expect(ranked.map((c) => c.signature), ['aaa', 'zzz']);
    });

    test('is stable regardless of input order', () {
      final one = _cluster(signature: 'a', bytes: 100, instances: 2);
      final two = _cluster(signature: 'b', bytes: 100, instances: 2);
      final three = _cluster(signature: 'c', bytes: 100, instances: 2);
      final forward = rankLeakClusters([
        one,
        two,
        three,
      ], projectPackages: _projectPackages).map((c) => c.signature);
      final reversed = rankLeakClusters([
        three,
        two,
        one,
      ], projectPackages: _projectPackages).map((c) => c.signature);
      expect(forward, reversed);
    });
  });

  group('LeakClustersView empty & warning states', () {
    testWidgets('no snapshot shows the capture hint', (tester) async {
      await tester.pumpWidget(
        _wrap(LeakClustersView(controller: _controller())),
      );
      expect(find.textContaining('Capture a snapshot'), findsOneWidget);
    });

    testWidgets('no clusters shows the suppressed-candidate empty state', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(
          _snap(
            clusters: const [],
            suppressedByAppFilter: 3,
            suppressedByLiveTree: 2,
          ),
        );
      await tester.pumpWidget(_wrap(LeakClustersView(controller: c)));
      await tester.pump();

      expect(find.textContaining('No leak clusters'), findsOneWidget);
      // 3 + 2 candidates were suppressed — surfaced honestly.
      expect(find.textContaining('5 candidates suppressed'), findsOneWidget);
    });

    testWidgets('renders the warnings strip when the analysis warns', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(
          _snap(
            clusters: [_cluster()],
            warnings: const ['heap capture truncated at 500k objects'],
          ),
        );
      await tester.pumpWidget(_wrap(LeakClustersView(controller: c)));
      await tester.pump();

      expect(find.textContaining('heap capture truncated'), findsOneWidget);
    });
  });

  group('LeakClustersView rows', () {
    testWidgets('renders headline, effective-origin chip, confidence and '
        'shallow-labeled bytes', (tester) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(
          _snap(
            clusters: [
              _cluster(
                className: 'LeakyScreenState',
                libraryUri: Uri.parse('dart:async'),
                anchorHopIndex: 0,
                anchorLib: _projectLib,
                bytes: 400,
                instances: 3,
              ),
            ],
          ),
        );
      await tester.pumpWidget(_wrap(LeakClustersView(controller: c)));
      await tester.pump();

      expect(find.text('LeakyScreenState'), findsOneWidget);
      // Declared origin is dart:async (sdk) but the app anchor makes the
      // EFFECTIVE origin project → the chip reads YOURS.
      expect(find.text('YOURS'), findsOneWidget);
      expect(find.text('CONFIRMED'), findsOneWidget);
      expect(find.textContaining('shallow'), findsOneWidget);
    });

    testWidgets('expanding a row reveals the representative path with the '
        'anchor highlight and the leaf class name', (tester) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(
          _snap(
            clusters: [
              _cluster(
                className: 'LeakyScreenState',
                libraryUri: Uri.parse('dart:async'),
                anchorHopIndex: 0,
                anchorLib: _projectLib,
                leafClassName: 'StreamSubscription',
              ),
            ],
          ),
        );
      await tester.pumpWidget(_wrap(LeakClustersView(controller: c)));
      await tester.pump();

      // Collapsed: no path tile yet.
      expect(find.byType(RetainingPathTile), findsNothing);

      await tester.tap(find.text('LeakyScreenState'));
      await tester.pump();

      expect(find.byType(RetainingPathTile), findsOneWidget);
      expect(find.text('yours'), findsOneWidget);
      expect(find.textContaining('StreamSubscription'), findsWidgets);
    });

    testWidgets('ranks project-anchored/confirmed clusters above the rest in '
        'render order', (tester) async {
      _setDesktopSize(tester);
      final c = _controller()
        ..debugAdd(
          _snap(
            clusters: [
              _cluster(
                className: 'DependencyLeak',
                libraryUri: _dependencyLib,
                confidence: LeakConfidence.heuristic,
                signature: 'z',
                bytes: 9999,
                instances: 99,
              ),
              _cluster(
                className: 'ProjectLeak',
                libraryUri: Uri.parse('dart:async'),
                anchorHopIndex: 0,
                anchorLib: _projectLib,
                signature: 'a',
                bytes: 10,
                instances: 1,
              ),
            ],
          ),
        );
      await tester.pumpWidget(_wrap(LeakClustersView(controller: c)));
      await tester.pump();

      final projectDy = tester.getTopLeft(find.text('ProjectLeak')).dy;
      final dependencyDy = tester.getTopLeft(find.text('DependencyLeak')).dy;
      expect(projectDy, lessThan(dependencyDy));
    });
  });

  group('workbench host wiring', () {
    tearDown(RadarSession.debugReset);

    testWidgets('the left rail routes to the leak clusters view', (
      tester,
    ) async {
      _setDesktopSize(tester);
      final connection = FakeRadarConnection();
      final memory = MemoryController(
        snapshotSource: FakeSnapshotSource(),
        connection: connection,
      )..debugAdd(_snap(clusters: [_cluster()]));
      RadarSession.install(
        RadarSession(
          connection: connection,
          memory: memory,
          perf: PerfDataController(),
          exporter: RecordingExporter(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 800,
              child: const LeakRadarMainScaffold(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LeakClustersView), findsNothing);
      await tester.tap(find.text('Leak clusters'));
      await tester.pump();
      expect(find.byType(LeakClustersView), findsOneWidget);
    });
  });
}
