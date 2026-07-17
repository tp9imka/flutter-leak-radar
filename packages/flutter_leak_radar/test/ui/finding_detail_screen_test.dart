// test/ui/finding_detail_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

HeapSnapshot snap(Map<String, int> c, {DateTime? at}) => HeapSnapshot(
  capturedAt: at ?? DateTime(2026),
  samples: [
    for (final e in c.entries)
      ClassSample(
        className: e.key,
        instancesCurrent: e.value,
        bytesCurrent: 0,
        timestamp: at ?? DateTime(2026),
      ),
  ],
);

LeakFinding testFinding({
  String className = 'TestBloc',
  int liveCount = 5,
  int growth = 3,
  List<int> series = const [2, 3, 5],
  List<DateTime>? captureTimes,
  String? tag,
}) => LeakFinding(
  className: className,
  kind: LeakKind.growth,
  severity: LeakSeverity.warning,
  liveCount: liveCount,
  growth: growth,
  series: series,
  captureTimes: captureTimes ?? const [],
  tag: tag,
);

Widget _wrap(Widget child) => MaterialApp(home: child);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  tearDown(() => LeakRadar.dispose());

  group('FindingDetailScreen — stats', () {
    testWidgets('renders class name in AppBar', (tester) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final finding = testFinding(className: 'HomeBloc');
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.text('HomeBloc'), findsWidgets);
    });

    testWidgets('shows live count stat', (tester) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final finding = testFinding(liveCount: 7);
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('shows net growth stat', (tester) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      // growth = last - first = 5 - 2 = 3
      final finding = testFinding(series: [2, 3, 5]);
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.text('+3'), findsWidgets);
    });

    testWidgets(
      'GROWTH tile and header render finding.growth, not last-first',
      (tester) async {
        await LeakRadar.debugInstall(
          LeakEngine(
            probe: const NoopHeapProbe(),
            analyzer: LeakAnalyzer(SuspectSet.empty()),
          ),
        );
        // finding.growth (last - min-baseline) = 6, but last - first = 3. The
        // detail screen must show the same number as the list row (+6).
        final finding = testFinding(series: [3, 4, 6], growth: 6);
        await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
        await tester.pumpAndSettle();

        expect(find.text('+6'), findsOneWidget); // GROWTH tile
        expect(find.textContaining('grew +6'), findsOneWidget); // header
        expect(find.text('+3'), findsNothing);
        expect(find.textContaining('grew +3'), findsNothing);
      },
    );

    testWidgets('shows Tracked status when tag set', (tester) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final finding = testFinding(tag: 'my-tag');
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.text('Tracked'), findsOneWidget);
    });

    testWidgets('shows Heap-inspected status when no tag', (tester) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final finding = testFinding(tag: null);
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Heap-inspected'), findsOneWidget);
    });

    testWidgets('bar chart paints without overflow', (tester) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final finding = testFinding(series: [1, 2, 3, 4, 5]);
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'precise finding (empty series) shows precise panel, not chart',
      (tester) async {
        await LeakRadar.debugInstall(
          LeakEngine(
            probe: const NoopHeapProbe(),
            analyzer: LeakAnalyzer(SuspectSet.empty()),
          ),
        );
        const finding = LeakFinding(
          className: '_LeakyScreenState',
          kind: LeakKind.notGced,
          severity: LeakSeverity.critical,
          liveCount: 3,
          growth: 0,
          series: <int>[],
          tag: 'LeakyScreen',
        );
        await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
        await tester.pumpAndSettle();
        expect(find.text('Precise tracking'), findsOneWidget);
        expect(find.text('still live after disposal'), findsOneWidget);
        expect(find.text('Live instances / capture'), findsNothing);
        expect(find.text('3'), findsOneWidget); // aggregated LIVE NOW count
      },
    );
  });

  group('FindingDetailScreen — retaining path', () {
    testWidgets('defers the fetch to a load button, then shows unavailable', (
      tester,
    ) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final finding = testFinding();
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      // Opening the screen must NOT trigger the (blocking) VM lookup: a load
      // affordance is shown instead of a spinner or the resolved path.
      expect(find.text('Load retaining path'), findsOneWidget);
      expect(find.textContaining('unavailable'), findsNothing);

      await tester.tap(find.text('Load retaining path'));
      await tester.pumpAndSettle();
      expect(find.textContaining('unavailable'), findsOneWidget);
    });

    testWidgets('shows retaining path when available', (tester) async {
      const path = RetainingPathView(
        gcRootType: 'class table',
        elements: [
          RetainingHop(objectType: 'Navigator', field: '_history'),
          RetainingHop(objectType: 'HomeBloc'),
        ],
      );
      final probe = FakeHeapProbe([], path: path);
      await LeakRadar.debugInstall(
        LeakEngine(probe: probe, analyzer: LeakAnalyzer(SuspectSet.empty())),
      );
      final finding = testFinding(className: 'HomeBloc');
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.textContaining('HomeBloc'), findsWidgets);
    });

    testWidgets('graph finding shows its carried path with no VM fetch', (
      tester,
    ) async {
      // NoopHeapProbe → a live VM lookup would return null. The path carried on
      // the finding (from the on-device snapshot) must render regardless.
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      const finding = LeakFinding(
        className: 'LeakyController',
        kind: LeakKind.retainedByNonLiveRoot,
        severity: LeakSeverity.critical,
        liveCount: 2,
        growth: 0,
        series: <int>[],
        retainingPath: RetainingPathView(
          gcRootType: 'Timer',
          elements: [
            RetainingHop(objectType: 'CarriedRootMarker', field: '_callback'),
            RetainingHop(objectType: 'LeakyController'),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('CarriedRootMarker'),
        findsWidgets,
        reason: 'carried snapshot path must render without a VM connection',
      );
    });
  });

  group('FindingDetailScreen — navigation', () {
    testWidgets(
      'tapping a finding row in LeakRadarScreen navigates to detail',
      (tester) async {
        final probe = FakeHeapProbe([
          snap({'NavBloc': 1}),
          snap({'NavBloc': 2}),
          snap({'NavBloc': 3}),
        ]);
        final engine = LeakEngine(
          probe: probe,
          analyzer: const LeakAnalyzer(
            SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
          ),
        );
        await LeakRadar.debugInstall(engine);
        await LeakRadar.scan();
        await LeakRadar.scan();
        await LeakRadar.scan();

        await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
        await tester.pumpAndSettle();

        expect(find.text('NavBloc'), findsOneWidget);
        await tester.tap(find.text('NavBloc'));
        await tester.pumpAndSettle();

        expect(find.byType(FindingDetailScreen), findsOneWidget);
      },
    );
  });

  group('_buildBottomRow', () {
    testWidgets('capture button has InkWell with non-null onTap', (
      tester,
    ) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final finding = testFinding();
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      // Target the capture button specifically — other tappable InkWells
      // (share, load-path) now also exist on the screen.
      final captureInk = find.ancestor(
        of: find.text('Capture .dartheap'),
        matching: find.byType(InkWell),
      );
      expect(captureInk, findsOneWidget);
      expect(tester.widget<InkWell>(captureInk).onTap, isNotNull);
    });

    testWidgets('bottom row renders without overflow', (tester) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final finding = testFinding();
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // ── T9: retainedByNonLiveRoot label ──────────────────────────────────────────

  group('FindingDetailScreen — retainedByNonLiveRoot label', () {
    testWidgets('severity strip shows readable label, not raw enum name', (
      tester,
    ) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      const finding = LeakFinding(
        className: 'LeakyController',
        kind: LeakKind.retainedByNonLiveRoot,
        severity: LeakSeverity.critical,
        liveCount: 1,
        growth: 0,
        series: <int>[],
      );
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();

      expect(
        find.text('Retained (non-live root)'),
        findsOneWidget,
        reason: 'readable label must appear',
      );
      expect(
        find.text('retainedByNonLiveRoot'),
        findsNothing,
        reason: 'raw enum name must not be visible',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('finding row shows readable label at 320 px without overflow', (
      tester,
    ) async {
      const path = RetainingPathView(
        gcRootType: 'class table',
        elements: [
          RetainingHop(objectType: 'WidgetsFlutterBinding', field: '_nodes'),
          RetainingHop(objectType: 'LeakyController'),
        ],
      );
      final probe = FakeHeapProbe([], path: path);
      await LeakRadar.debugInstall(
        LeakEngine(probe: probe, analyzer: LeakAnalyzer(SuspectSet.empty())),
      );

      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const finding = LeakFinding(
        className: 'LeakyController',
        kind: LeakKind.retainedByNonLiveRoot,
        severity: LeakSeverity.critical,
        liveCount: 2,
        growth: 0,
        series: <int>[],
      );
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();

      expect(find.text('Retained (non-live root)'), findsOneWidget);
      // Path is now loaded on demand; fetch it, then assert it renders.
      await tester.tap(find.text('Load retaining path'));
      await tester.pumpAndSettle();
      expect(find.textContaining('WidgetsFlutterBinding'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('LeakFinding.firstSeen', () {
    test('returns null when captureTimes is empty', () {
      final f = testFinding(series: [0, 1, 2], captureTimes: []);
      expect(f.firstSeen, isNull);
    });

    test('returns first time where series > 0', () {
      final t0 = DateTime(2026, 1, 1, 10, 0);
      final t1 = DateTime(2026, 1, 1, 10, 5);
      final t2 = DateTime(2026, 1, 1, 10, 10);
      final f = testFinding(series: [0, 1, 2], captureTimes: [t0, t1, t2]);
      expect(f.firstSeen, equals(t1));
    });

    test('returns null when all series values are 0', () {
      final t0 = DateTime(2026, 1, 1, 10, 0);
      final f = testFinding(series: [0, 0], captureTimes: [t0, t0]);
      expect(f.firstSeen, isNull);
    });
  });
}
