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
}) =>
    LeakFinding(
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
      await LeakRadar.debugInstall(LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ));
      final finding = testFinding(className: 'HomeBloc');
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.text('HomeBloc'), findsWidgets);
    });

    testWidgets('shows live count stat', (tester) async {
      await LeakRadar.debugInstall(LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ));
      final finding = testFinding(liveCount: 7);
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('shows net growth stat', (tester) async {
      await LeakRadar.debugInstall(LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ));
      // growth = last - first = 5 - 2 = 3
      final finding = testFinding(series: [2, 3, 5]);
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.text('+3'), findsWidgets);
    });

    testWidgets('shows Tracked status when tag set', (tester) async {
      await LeakRadar.debugInstall(LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ));
      final finding = testFinding(tag: 'my-tag');
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.text('Tracked'), findsOneWidget);
    });

    testWidgets('shows Heap-inspected status when no tag', (tester) async {
      await LeakRadar.debugInstall(LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ));
      final finding = testFinding(tag: null);
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Heap-inspected'), findsOneWidget);
    });

    testWidgets('bar chart paints without overflow', (tester) async {
      await LeakRadar.debugInstall(LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ));
      final finding = testFinding(series: [1, 2, 3, 4, 5]);
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('FindingDetailScreen — retaining path', () {
    testWidgets('shows spinner while fetching, then unavailable',
        (tester) async {
      await LeakRadar.debugInstall(LeakEngine(
        probe: const NoopHeapProbe(),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ));
      final finding = testFinding();
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pump();
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
      await LeakRadar.debugInstall(LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      ));
      final finding = testFinding(className: 'HomeBloc');
      await tester.pumpWidget(_wrap(FindingDetailScreen(finding: finding)));
      await tester.pumpAndSettle();
      expect(find.textContaining('HomeBloc'), findsWidgets);
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
      final f = testFinding(
        series: [0, 1, 2],
        captureTimes: [t0, t1, t2],
      );
      expect(f.firstSeen, equals(t1));
    });

    test('returns null when all series values are 0', () {
      final t0 = DateTime(2026, 1, 1, 10, 0);
      final f = testFinding(series: [0, 0], captureTimes: [t0, t0]);
      expect(f.firstSeen, isNull);
    });
  });
}
