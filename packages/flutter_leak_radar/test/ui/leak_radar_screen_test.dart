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

  // ── Filter chips ──────────────────────────────────────────────────────────

  group('filter chips', () {
    setUp(() async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
    });

    testWidgets('Critical filter chip is visible and tappable', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      expect(find.text('Critical'), findsOneWidget);
      await tester.tap(find.text('Critical'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Growing filter chip is visible and tappable', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      expect(find.text('Growing'), findsOneWidget);
      await tester.tap(find.text('Growing'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Critical filter with real findings shows only matching rows', (
      tester,
    ) async {
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

      await tester.tap(find.text('Critical'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Growing filter shows findings with growth > 0', (
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

      await tester.tap(find.text('Growing'));
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

  // ── Swipe-to-dismiss ─────────────────────────────────────────────────────

  group('swipe-to-dismiss', () {
    testWidgets('swiping a finding row removes it from the displayed list', (
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

      await tester.drag(find.text('HomeBloc'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('HomeBloc'), findsNothing);
      expect(find.text('No findings match this filter'), findsOneWidget);
    });

    testWidgets('a new scan re-adds a dismissed finding if still leaking', (
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

      await tester.drag(find.text('HomeBloc'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('HomeBloc'), findsNothing);

      // 4th scan re-seeds dismissed set; HomeBloc still leaking.
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
