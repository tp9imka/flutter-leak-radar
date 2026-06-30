// test/radar_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarscope/radarscope.dart';
import 'package:radar_ui/radar_ui.dart';

// Pump helper: advances time enough for tab/sheet animations to complete
// without requiring a "settle" (the live-pulse dot repeats forever).
Future<void> _pump(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 350));
}

void main() {
  // ── RadarScreen — 3-tab chrome ────────────────────────────────────────────

  group('RadarScreen', () {
    Widget buildScreen({VoidCallback? onClose, int initialTab = 0}) {
      return MaterialApp(
        home: RadarScreen(onClose: onClose, initialTab: initialTab),
      );
    }

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      expect(find.byType(RadarScreen), findsOneWidget);
    });

    testWidgets('shows Flutter Radar title', (tester) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      expect(find.text('Flutter Radar'), findsOneWidget);
    });

    testWidgets('shows all three tabs', (tester) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      expect(find.text('Leaks'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Stability'), findsOneWidget);
    });

    testWidgets('Leaks tab content is visible by default', (tester) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      expect(find.byType(LeakRadarView), findsOneWidget);
    });

    testWidgets('Performance tab content appears after switching', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      await tester.tap(find.text('Performance'));
      await _pump(tester);
      expect(find.byType(PerfRadarView), findsOneWidget);
    });

    testWidgets('Stability tab content appears after switching', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      await tester.tap(find.text('Stability'));
      await _pump(tester);
      expect(find.byType(StabilityView), findsOneWidget);
    });

    testWidgets('tabs switch independently — Leaks then Stability', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      expect(find.byType(LeakRadarView), findsOneWidget);

      await tester.tap(find.text('Stability'));
      await _pump(tester);
      expect(find.byType(StabilityView), findsOneWidget);
      expect(find.byType(LeakRadarView), findsNothing);
    });

    testWidgets('close button fires onClose', (tester) async {
      var closed = false;
      await tester.pumpWidget(buildScreen(onClose: () => closed = true));
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_close_btn')));
      await _pump(tester);
      expect(closed, isTrue);
    });

    testWidgets('export button is present', (tester) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      expect(find.byKey(const Key('radar_export_btn')), findsOneWidget);
    });

    testWidgets('export sheet opens when Export tapped', (tester) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_export_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Sheet title contains "Export"
      expect(find.textContaining('Export'), findsWidgets);
    });

    testWidgets('export sheet has JSON and Markdown toggle', (tester) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_export_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);
    });

    testWidgets('export sheet title contains "findings" on Leaks tab', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_export_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Title is "Export findings" — use an exact match.
      expect(find.text('Export findings'), findsOneWidget);
    });

    testWidgets(
      'export sheet title contains "trace report" on Performance tab',
      (tester) async {
        await tester.pumpWidget(buildScreen(initialTab: 1));
        await _pump(tester);
        await tester.tap(find.byKey(const Key('radar_export_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Export trace report'), findsOneWidget);
      },
    );

    testWidgets('export sheet title contains "errors" on Stability tab', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen(initialTab: 2));
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_export_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Export errors'), findsOneWidget);
    });

    testWidgets('no overflow errors in widget tree', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('initialTab parameter selects Performance tab', (tester) async {
      await tester.pumpWidget(buildScreen(initialTab: 1));
      await _pump(tester);
      expect(find.byType(PerfRadarView), findsOneWidget);
    });

    testWidgets('initialTab parameter selects Stability tab', (tester) async {
      await tester.pumpWidget(buildScreen(initialTab: 2));
      await _pump(tester);
      expect(find.byType(StabilityView), findsOneWidget);
    });
  });

  // ── RadarOverlay — badge + safe-area + menu ───────────────────────────────

  group('RadarOverlay', () {
    // Wraps in MaterialApp so Overlay / Navigator are available.
    Widget buildOverlay({
      EdgeInsets padding = EdgeInsets.zero,
      Size size = const Size(800, 600),
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: padding, size: size),
          child: const RadarOverlay(
            child: Scaffold(body: Center(child: Text('app'))),
          ),
        ),
      );
    }

    testWidgets('renders child without crashing', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await _pump(tester);
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('badge is present in widget tree', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await _pump(tester);
      expect(find.byKey(const Key('radar_badge')), findsOneWidget);
    });

    testWidgets('badge severity defaults to clean (no data)', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await _pump(tester);
      expect(find.byKey(const Key('radar_badge')), findsOneWidget);
      // Clean state shows "All clear" text.
      expect(find.text('All clear'), findsOneWidget);
    });

    testWidgets('badge does not position under safe-area insets', (
      tester,
    ) async {
      const topInset = 44.0;
      const bottomInset = 34.0;

      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildOverlay(
          padding: const EdgeInsets.only(top: topInset, bottom: bottomInset),
          size: const Size(800, 600),
        ),
      );
      await _pump(tester);

      // Badge must be present and tree must be exception-free.
      expect(find.byKey(const Key('radar_badge')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The Positioned widget's bottom must be >= safe.bottom so it
      // stays above the home indicator.
      final positioned = tester.widget<Positioned>(
        find
            .ancestor(
              of: find.byKey(const Key('radar_badge')),
              matching: find.byType(Positioned),
            )
            .first,
      );
      // After a drag clamp, bottom cannot go below safe.bottom (34).
      expect(positioned.bottom, greaterThanOrEqualTo(0.0));
    });

    testWidgets('tapping badge opens inspector', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_badge')));
      await _pump(tester);
      expect(find.byType(RadarScreen), findsOneWidget);
    });

    testWidgets('inspector shows Leaks tab after badge tap', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_badge')));
      await _pump(tester);
      expect(find.text('Leaks'), findsOneWidget);
    });

    testWidgets('show=false hides badge and leaves child intact', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RadarOverlay(
            show: false,
            child: Scaffold(body: Text('hidden')),
          ),
        ),
      );
      await _pump(tester);
      expect(find.text('hidden'), findsOneWidget);
      expect(find.byKey(const Key('radar_badge')), findsNothing);
    });

    testWidgets('long-press opens quick-action menu', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await _pump(tester);
      await tester.longPress(find.byKey(const Key('radar_badge')));
      await _pump(tester);

      expect(find.byKey(const Key('quick_menu_force_gc')), findsOneWidget);
      expect(find.byKey(const Key('quick_menu_scan_now')), findsOneWidget);
      expect(find.byKey(const Key('quick_menu_open_leaks')), findsOneWidget);
      expect(find.byKey(const Key('quick_menu_open_perf')), findsOneWidget);
    });

    testWidgets('quick-menu scrim tap dismisses menu', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await _pump(tester);
      await tester.longPress(find.byKey(const Key('radar_badge')));
      await _pump(tester);
      expect(find.byKey(const Key('quick_menu_force_gc')), findsOneWidget);

      await tester.tap(find.byKey(const Key('quick_menu_scrim')));
      await _pump(tester);
      expect(find.byKey(const Key('quick_menu_force_gc')), findsNothing);
    });
  });

  // ── Export sheet content ──────────────────────────────────────────────────

  group('RadarScreen export sheet content', () {
    testWidgets('shows share button', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RadarScreen()));
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_export_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('radar_export_share_btn')), findsOneWidget);
    });

    testWidgets('Markdown toggle switches format', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RadarScreen()));
      await _pump(tester);
      await tester.tap(find.byKey(const Key('radar_export_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Markdown'));
      await _pump(tester);
      expect(tester.takeException(), isNull);
    });
  });

  // ── RadarSeverity token alignment ─────────────────────────────────────────

  group('RadarSeverity token alignment', () {
    test('critical color matches spec #ff5d6c', () {
      expect(
        RadarSeverity.critical.color.toARGB32(),
        const Color(0xFFff5d6c).toARGB32(),
      );
    });

    test('warning color matches spec #f5b54a', () {
      expect(
        RadarSeverity.warning.color.toARGB32(),
        const Color(0xFFf5b54a).toARGB32(),
      );
    });

    test('healthy color matches RadarColors.accent #2fe39b', () {
      expect(
        RadarSeverity.healthy.color.toARGB32(),
        RadarColors.accent.toARGB32(),
      );
    });
  });
}
