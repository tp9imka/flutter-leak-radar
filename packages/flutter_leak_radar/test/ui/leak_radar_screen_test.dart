// test/ui/leak_radar_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

HeapSnapshot snap(Map<String, int> c) => HeapSnapshot(
  capturedAt: DateTime(2026),
  samples: [
    for (final e in c.entries)
      ClassSample(
        className: e.key,
        instancesCurrent: e.value,
        bytesCurrent: 0,
        timestamp: DateTime(2026),
      ),
  ],
);

/// Finds the Scan now button by its stable key.
Finder get _scanBtn => find.byKey(const Key('leak_radar_scan_btn'));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  tearDown(() => LeakRadar.dispose());

  // ── Summary row: stats ──────────────────────────────────────────────────────

  group('_SummaryRow', () {
    testWidgets(
      'GC action in overflow menu; class/instance stats appear exactly once',
      (tester) async {
        final probe = FakeHeapProbe([
          snap({'HomeBloc': 1}),
          snap({'HomeBloc': 2}),
          snap({'HomeBloc': 3}),
        ]);
        await LeakRadar.debugInstall(
          LeakEngine(
            probe: probe,
            analyzer: const LeakAnalyzer(
              SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
            ),
          ),
        );
        await LeakRadar.scan();
        await LeakRadar.scan();
        await LeakRadar.scan();

        await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
        await tester.pumpAndSettle();

        // Force GC is now exposed in the LeakRadarView's bottom action bar
        // (always visible) and still available in the AppBar overflow menu.
        expect(
          find.byKey(const Key('leak_force_gc_btn')),
          findsOneWidget,
          reason: 'Force GC button must be in the bottom action bar',
        );

        // The overflow menu still contains "Force GC & rescan".
        expect(find.byTooltip('More'), findsOneWidget);
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Force GC'), findsWidgets);
        // Dismiss menu.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Stats live in exactly ONE place (the bottom bar), not duplicated in
        // the summary row.
        expect(find.textContaining('instances'), findsOneWidget);
      },
    );

    testWidgets('summary row does not overflow at 320 px with many findings', (
      tester,
    ) async {
      // 40 distinct growing classes → wide severity tallies.
      final grown = {for (var i = 0; i < 40; i++) 'Bloc$i': i + 2};
      final probe = FakeHeapProbe([
        snap({for (final k in grown.keys) k: 1}),
        snap(grown),
      ]);
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: probe,
          analyzer: const LeakAnalyzer(
            SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
          ),
        ),
      );
      await LeakRadar.scan();
      await LeakRadar.scan();

      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  // ── Overflow regression ───────────────────────────────────────────────────

  group('_FindingRow — narrow-width overflow regression', () {
    testWidgets(
      'no RenderFlex overflow at 320 px screen width with sparkline series',
      (tester) async {
        final probe = FakeHeapProbe([
          snap({'HomeBloc': 1}),
          snap({'HomeBloc': 2}),
          snap({'HomeBloc': 3}),
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

        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('HomeBloc'), findsOneWidget);
      },
    );
  });

  // ── Scan now ──────────────────────────────────────────────────────────────

  testWidgets('shows findings after Scan now', (tester) async {
    final probe = FakeHeapProbe([
      snap({'HomeBloc': 1}),
      snap({'HomeBloc': 2}),
      snap({'HomeBloc': 3}),
    ]);
    final engine = LeakEngine(
      probe: probe,
      analyzer: const LeakAnalyzer(
        SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
      ),
    );
    await LeakRadar.debugInstall(engine);
    // Pre-seed two scans so the third (triggered by the button) produces a
    // growth finding.
    await LeakRadar.scan();
    await LeakRadar.scan();

    await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
    // Tap via stable key to avoid ambiguity with other 'Scan now' text.
    await tester.tap(_scanBtn);
    await tester.pumpAndSettle();

    expect(find.text('HomeBloc'), findsOneWidget);
  });

  // ── Action buttons ────────────────────────────────────────────────────────

  group('LeakRadarScreen — action buttons', () {
    setUp(() async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
    });

    testWidgets('shows Export and Settings action buttons', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();
      expect(find.byTooltip('Export'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('Export button opens LeakExportSheet', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      await tester.tap(find.byTooltip('Export'));
      await tester.pumpAndSettle();

      expect(find.byType(LeakExportSheet), findsOneWidget);
    });

    testWidgets('empty state is shown when no findings', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();
      expect(find.text('No leaks detected'), findsOneWidget);
    });

    testWidgets('scan now button does not throw', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      await tester.tap(_scanBtn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Scan now button shows snackbar with Heap captured text', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      await tester.tap(_scanBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Heap captured'), findsOneWidget);
    });
  });

  // ── Filter chips (kind-based) ─────────────────────────────────────────────

  group('filter chips', () {
    setUp(() async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
    });

    testWidgets('sort + filter controls are collapsed by default', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pumpAndSettle();

      // Chips + sort headers are hidden until the disclosure is expanded, so
      // the leak list gets the vertical space.
      expect(find.text('all'), findsNothing);
      expect(find.text('not disposed'), findsNothing);

      await tester.tap(find.text('filters'));
      await tester.pumpAndSettle();
      expect(find.text('all'), findsOneWidget);
      expect(find.text('not disposed'), findsOneWidget);
    });

    testWidgets('"all" filter chip is visible and tappable', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pumpAndSettle();

      // Sort + filter controls collapse by default; expand them first.
      await tester.tap(find.text('filters'));
      await tester.pumpAndSettle();

      expect(find.text('all'), findsOneWidget);
      await tester.tap(find.text('all'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('"growth" filter chip is visible and tappable', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('filters'));
      await tester.pumpAndSettle();

      // 'growth' appears in both the sort header row and the filter chip row.
      expect(find.text('growth'), findsWidgets);
      // The filter chip row is rendered after the sort row, so the chip is last.
      await tester.tap(find.text('growth').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '"growth" filter with real findings still shows matching rows',
      (tester) async {
        final probe = FakeHeapProbe([
          snap({'CriticalBloc': 1}),
          snap({'CriticalBloc': 3}),
          snap({'CriticalBloc': 6}),
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

        expect(find.text('CriticalBloc'), findsOneWidget);

        // Expand the collapsed sort/filter controls before using them.
        await tester.tap(find.text('filters'));
        await tester.pumpAndSettle();

        // Tap the filter chip — 'growth' appears in both sort row and chip row;
        // the chip is the last widget found in tree order.
        await tester.tap(find.text('growth').last);
        await tester.pumpAndSettle();
        // Growth finding remains visible after selecting growth filter.
        expect(find.text('CriticalBloc'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('"growth" filter shows findings with growth > 0', (
      tester,
    ) async {
      final probe = FakeHeapProbe([
        snap({'GrowingBloc': 1}),
        snap({'GrowingBloc': 2}),
        snap({'GrowingBloc': 3}),
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

      expect(find.text('GrowingBloc'), findsOneWidget);

      // Expand the collapsed sort/filter controls before using them.
      await tester.tap(find.text('filters'));
      await tester.pumpAndSettle();

      // Tap the filter chip — 'growth' appears in both sort row and chip row;
      // the chip is the last widget found in tree order.
      await tester.tap(find.text('growth').last);
      await tester.pumpAndSettle();
      // Finding has growth > 0, so it remains visible after filter.
      expect(find.text('GrowingBloc'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── Clear leaks ───────────────────────────────────────────────────────────

  group('Clear leaks', () {
    testWidgets('tapping Clear leaks in overflow menu empties the list', (
      tester,
    ) async {
      final probe = FakeHeapProbe([
        snap({'HomeBloc': 1}),
        snap({'HomeBloc': 2}),
        snap({'HomeBloc': 3}),
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

      expect(find.text('HomeBloc'), findsOneWidget);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear leaks'));
      await tester.pumpAndSettle();

      expect(find.text('HomeBloc'), findsNothing);
      expect(find.text('No leaks detected'), findsOneWidget);
    });
  });

  // ── Scan re-adds findings ─────────────────────────────────────────────────

  group('scan re-adds findings', () {
    testWidgets('a new scan brings back a previously unseen finding', (
      tester,
    ) async {
      // 3 snapshots: 2 pre-seeded, 1 consumed by button tap.
      // FakeHeapProbe repeats the last snapshot, so a second button tap
      // also produces a growth finding.
      final probe = FakeHeapProbe([
        snap({'HomeBloc': 1}),
        snap({'HomeBloc': 2}),
        snap({'HomeBloc': 3}),
      ]);
      final engine = LeakEngine(
        probe: probe,
        analyzer: const LeakAnalyzer(
          SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
        ),
      );
      await LeakRadar.debugInstall(engine);
      // Pre-seed 2 scans; no finding yet.
      await LeakRadar.scan();
      await LeakRadar.scan();

      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pumpAndSettle();

      // 3rd scan (button) produces HomeBloc growth finding.
      await tester.tap(_scanBtn);
      await tester.pumpAndSettle();

      expect(find.text('HomeBloc'), findsOneWidget);

      // 4th scan (button) — finding still present.
      await tester.tap(_scanBtn);
      await tester.pumpAndSettle();

      expect(find.text('HomeBloc'), findsOneWidget);
    });
  });

  // ── Summary row ───────────────────────────────────────────────────────────

  group('summary row', () {
    testWidgets('shows severity counts in summary after scan with findings', (
      tester,
    ) async {
      final probe = FakeHeapProbe([
        snap({'CritBloc': 1}),
        snap({'CritBloc': 5}),
        snap({'CritBloc': 10}),
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

      expect(tester.takeException(), isNull);

      // At least one severity count is shown in the summary row.
      final hasCritical = find.textContaining('critical').evaluate().isNotEmpty;
      final hasWarning = find.textContaining('warning').evaluate().isNotEmpty;
      final hasInfo = find.textContaining('info').evaluate().isNotEmpty;
      expect(hasCritical || hasWarning || hasInfo, isTrue);
    });
  });
}
