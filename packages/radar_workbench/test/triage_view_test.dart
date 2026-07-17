import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

// ── Harness ─────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {Size size = const Size(1280, 800)}) => MaterialApp(
  home: Theme(
    data: radarDarkTheme(),
    child: Scaffold(
      body: SizedBox.fromSize(size: size, child: child),
    ),
  ),
);

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

GraphRetainingPath _path() => const GraphRetainingPath(
  hops: [GraphHop(className: 'OwnerState', field: '_sub')],
  rootKind: RootKind.stream,
);

GraphLeakCluster _cluster({
  required String signature,
  String className = 'LeakyThing',
}) => GraphLeakCluster(
  className: className,
  libraryUri: Uri.parse('package:my_app/x.dart'),
  instanceCount: 2,
  retainedShallowBytes: 100,
  representativePath: _path(),
  rootKind: RootKind.stream,
  confidence: LeakConfidence.heuristic,
  signature: signature,
);

SnapshotBundle _snap(List<GraphLeakCluster> clusters) => SnapshotBundle(
  id: 1,
  capturedAt: DateTime(2026, 1, 1, 12),
  label: 'Snapshot 1',
  histogram: const [],
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

MemoryController _controller(List<GraphLeakCluster> clusters) =>
    MemoryController(
      snapshotSource: FakeSnapshotSource(),
      connection: FakeRadarConnection(),
    )..debugAdd(_snap(clusters));

TriageEntry _entry(
  String signature, {
  TriageStatus status = TriageStatus.known,
  String? note,
  String? className,
  DateTime? goneSince,
}) => TriageEntry(
  signature: signature,
  firstSeen: DateTime(2026, 6, 1),
  status: status,
  note: note,
  className: className,
  goneSince: goneSince,
);

void main() {
  group('cluster row chips', () {
    testWidgets('an unseen signature renders a NEW chip', (tester) async {
      _setSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(controller: _controller([_cluster(signature: 'a')])),
        ),
      );
      await tester.pump();
      expect(find.text('NEW'), findsOneWidget);
    });

    testWidgets('a known baseline signature renders a KNOWN chip', (
      tester,
    ) async {
      _setSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([_cluster(signature: 'a')]),
            initialTriage: TriageStore.empty.upsert(_entry('a')),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('KNOWN'), findsOneWidget);
      expect(find.text('NEW'), findsNothing);
    });
  });

  group('GONE section (the payoff)', () {
    testWidgets('lists a fixed signature at the TOP, above the cluster list', (
      tester,
    ) async {
      _setSize(tester, const Size(1280, 800));
      // Baseline knew sigGone + sigStay; current heap only has sigStay → the
      // fix for sigGone landed.
      final baseline = TriageStore.empty
          .upsert(_entry('sigGone', note: 'fixed the stream leak'))
          .upsert(_entry('sigStay'));
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([
              _cluster(signature: 'sigStay', className: 'StillLeaky'),
            ]),
            initialTriage: baseline,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Fixed since last session'), findsOneWidget);
      expect(find.text('fixed the stream leak'), findsOneWidget);

      final goneDy = tester
          .getTopLeft(find.textContaining('Fixed since last session'))
          .dy;
      final rowDy = tester.getTopLeft(find.text('StillLeaky')).dy;
      expect(goneDy, lessThan(rowDy));
    });

    testWidgets('GONE row names the class and shows "fixed since <date>" when '
        'a retirement date is known', (tester) async {
      _setSize(tester, const Size(1280, 800));
      final baseline = TriageStore.empty.upsert(
        _entry(
          'sigGone',
          className: 'FixedLeak',
          goneSince: DateTime(2026, 6, 15),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([_cluster(signature: 'other')]),
            initialTriage: baseline,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('FixedLeak'), findsOneWidget);
      expect(find.text('fixed since 2026-06-15'), findsOneWidget);
    });

    testWidgets('GONE row reads "fixed" (no date) before a retirement date is '
        'stamped', (tester) async {
      _setSize(tester, const Size(1280, 800));
      final baseline = TriageStore.empty.upsert(
        _entry('sigGone', className: 'FixedLeak'),
      );
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([_cluster(signature: 'other')]),
            initialTriage: baseline,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('fixed'), findsOneWidget);
    });

    testWidgets('no GONE section when every known signature is still present', (
      tester,
    ) async {
      _setSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([_cluster(signature: 'a')]),
            initialTriage: TriageStore.empty.upsert(_entry('a')),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Fixed since last session'), findsNothing);
    });
  });

  group('since-last-session toggle', () {
    testWidgets('filters the list to NEW while keeping GONE visible', (
      tester,
    ) async {
      _setSize(tester, const Size(1280, 800));
      final baseline = TriageStore.empty
          .upsert(_entry('known'))
          .upsert(_entry('gone', note: 'gone note'));
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([
              _cluster(signature: 'known', className: 'KnownLeak'),
              _cluster(signature: 'brandNew', className: 'NewLeak'),
            ]),
            initialTriage: baseline,
          ),
        ),
      );
      await tester.pump();

      // Off: both clusters shown.
      expect(find.text('KnownLeak'), findsOneWidget);
      expect(find.text('NewLeak'), findsOneWidget);

      await tester.tap(find.text('Since last session'));
      await tester.pump();

      // On: only the NEW cluster remains; GONE stays visible.
      expect(find.text('NewLeak'), findsOneWidget);
      expect(find.text('KnownLeak'), findsNothing);
      expect(find.text('gone note'), findsOneWidget);
    });

    testWidgets('hiding a KNOWN row never turns it into a false GONE', (
      tester,
    ) async {
      _setSize(tester, const Size(1280, 800));
      // 'known' is present in the current heap; the toggle hides its row but it
      // must NOT be reported as fixed.
      final baseline = TriageStore.empty.upsert(_entry('known'));
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([
              _cluster(signature: 'known', className: 'KnownLeak'),
              _cluster(signature: 'brandNew', className: 'NewLeak'),
            ]),
            initialTriage: baseline,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Since last session'));
      await tester.pump();

      // The hidden KNOWN row did not leak into a "fixed since last session".
      expect(find.textContaining('Fixed since last session'), findsNothing);
    });
  });

  group('acknowledge action', () {
    testWidgets('ACK with a note updates the chip and reports the store', (
      tester,
    ) async {
      _setSize(tester, const Size(1280, 800));
      TriageStore? reported;
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([_cluster(signature: 'a')]),
            initialTriage: TriageStore.empty.upsert(_entry('a')),
            onTriageChanged: (store) => reported = store,
            clock: () => DateTime(2026, 7, 15),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acknowledge…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'JIRA-42');
      await tester.tap(find.widgetWithText(TextButton, 'Acknowledge'));
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      final entry = reported!.entryFor('a')!;
      expect(entry.status, TriageStatus.acknowledged);
      expect(entry.note, 'JIRA-42');
      // The row chip flipped NEW/KNOWN → ACK.
      expect(find.text('ACK'), findsOneWidget);
    });

    testWidgets('cancelling the ACK dialog reports nothing', (tester) async {
      _setSize(tester, const Size(1280, 800));
      var reportedCount = 0;
      await tester.pumpWidget(
        _wrap(
          LeakClustersView(
            controller: _controller([_cluster(signature: 'a')]),
            onTriageChanged: (_) => reportedCount++,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acknowledge…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(reportedCount, 0);
    });
  });

  group('width safety', () {
    for (final width in const [722.0, 800.0, 1280.0]) {
      testWidgets('renders chips + toggle + GONE without overflow at $width', (
        tester,
      ) async {
        final size = Size(width, 600);
        _setSize(tester, size);
        final baseline = TriageStore.empty
            .upsert(_entry('gone', note: 'a reasonably long note about a fix'))
            .upsert(_entry('known'));
        await tester.pumpWidget(
          _wrap(
            LeakClustersView(
              controller: _controller([
                _cluster(
                  signature: 'known',
                  className: 'AReasonablyLongLeakyClassName',
                ),
                _cluster(signature: 'brandNew', className: 'AnotherLeak'),
              ]),
              initialTriage: baseline,
            ),
            size: size,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
