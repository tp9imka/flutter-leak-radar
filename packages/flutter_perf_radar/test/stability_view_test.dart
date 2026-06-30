// packages/flutter_perf_radar/test/stability_view_test.dart
//
// Widget tests for StabilityView + StabilityScreen.
// Covers §B3 spec: Errors sub-tab (grouping, sort, drill-down, empty state)
// and Stalls sub-tab (color-graded durations, bar, empty state).
//
// ErrorRecord carries: message, context, clockMicros, stackTraceString.
// StallRecord carries: durationMicros, clockMicros.
// No "cause" field exists on StallRecord — it is intentionally absent here.

import 'package:flutter/material.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _harness(StabilitySnapshot snapshot) => MaterialApp(
  home: Scaffold(body: StabilityViewBody(snapshot: snapshot)),
);

// ── Fixture data ──────────────────────────────────────────────────────────────

const _emptySnapshot = StabilitySnapshot(
  errorCount: 0,
  stallCount: 0,
  recentErrors: [],
  recentStalls: [],
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('StabilityScreen', () {
    testWidgets('renders Scaffold with Stability app-bar title', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: StabilityScreen()));
      expect(find.text('Stability'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('calls onClose when close button tapped', (tester) async {
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(home: StabilityScreen(onClose: () => closed = true)),
      );
      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    });
  });

  group('StabilityView — sub-tab bar', () {
    testWidgets('shows Errors and Stalls sub-tab chips', (tester) async {
      await tester.pumpWidget(_harness(_emptySnapshot));
      expect(find.text('Errors'), findsOneWidget);
      expect(find.text('Stalls'), findsOneWidget);
    });

    testWidgets('defaults to Errors sub-tab', (tester) async {
      await tester.pumpWidget(_harness(_emptySnapshot));
      // Empty errors state message confirms the Errors tab is active
      expect(find.textContaining('No errors captured'), findsOneWidget);
    });

    testWidgets('tapping Stalls switches to stalls body', (tester) async {
      await tester.pumpWidget(_harness(_emptySnapshot));
      await tester.tap(find.text('Stalls'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No stalls detected'), findsOneWidget);
    });
  });

  group('StabilityView — Errors sub-tab (empty state)', () {
    testWidgets('shows empty state when no errors', (tester) async {
      await tester.pumpWidget(_harness(_emptySnapshot));
      expect(find.textContaining('No errors captured'), findsOneWidget);
    });

    testWidgets('header shows 0 distinct · 0 total', (tester) async {
      await tester.pumpWidget(_harness(_emptySnapshot));
      expect(find.textContaining('0 distinct'), findsOneWidget);
      expect(find.textContaining('0 total'), findsOneWidget);
    });
  });

  group('StabilityView — Errors sub-tab (grouping)', () {
    testWidgets('groups duplicate errors and shows ×repeats', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 3,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'Null check failure',
            context: 'FlutterError',
            clockMicros: 1000000,
          ),
          ErrorRecord(
            message: 'Null check failure',
            context: 'FlutterError',
            clockMicros: 2000000,
          ),
          ErrorRecord(
            message: 'Null check failure',
            context: 'FlutterError',
            clockMicros: 3000000,
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));

      // Should show only 1 row (grouped)
      expect(find.text('×3'), findsOneWidget);
      // Distinct=1, total pulled from snapshot.errorCount=3
      expect(find.textContaining('1 distinct'), findsOneWidget);
      expect(find.textContaining('3 total'), findsOneWidget);
    });

    testWidgets('two distinct errors produce two rows', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 2,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'Error A',
            context: 'FlutterError',
            clockMicros: 1000000,
          ),
          ErrorRecord(
            message: 'Error B',
            context: 'FlutterError',
            clockMicros: 2000000,
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));

      expect(find.textContaining('Error A'), findsOneWidget);
      expect(find.textContaining('Error B'), findsOneWidget);
      // Each appears once so ×1 each
      expect(find.text('×1'), findsNWidgets(2));
    });

    testWidgets('errors with null context show no type tag', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 1,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'Bare error',
            context: null,
            clockMicros: 1000000,
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));

      expect(find.textContaining('Bare error'), findsOneWidget);
      // 'FlutterError' tag must not appear since context is null
      expect(find.text('FlutterError'), findsNothing);
    });
  });

  group('StabilityView — Errors sub-tab (sort toggle)', () {
    testWidgets('sort toggle is visible when errors present', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 1,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'Oops',
            context: 'FlutterError',
            clockMicros: 1000000,
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));

      // Toggle button shows current sort mode
      expect(find.textContaining('repeats'), findsOneWidget);
    });

    testWidgets('tapping sort toggle switches between repeats and time', (
      tester,
    ) async {
      const snapshot = StabilitySnapshot(
        errorCount: 1,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'E1',
            context: 'FlutterError',
            clockMicros: 1000000,
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));

      // Initial state: 'repeats'
      expect(find.textContaining('repeats'), findsOneWidget);

      // Tap toggle
      await tester.tap(find.textContaining('repeats'));
      await tester.pump();

      expect(find.textContaining('time'), findsOneWidget);

      // Tap again
      await tester.tap(find.textContaining('time'));
      await tester.pump();

      expect(find.textContaining('repeats'), findsOneWidget);
    });
  });

  group('StabilityView — Errors sub-tab (stack trace drill-down)', () {
    testWidgets('tapping an error row opens detail screen', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 1,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'Fatal: null deref',
            context: 'FlutterError',
            clockMicros: 1000000,
            stackTraceString:
                '#0  main (file://main.dart:10:3)\n'
                '#1  runApp (file://app.dart:5:1)',
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));

      // Tap the error row
      await tester.tap(find.textContaining('Fatal: null deref'));
      await tester.pumpAndSettle();

      // Detail screen: error message + stack frame
      expect(find.textContaining('Fatal: null deref'), findsWidgets);
      expect(find.textContaining('#0  main'), findsOneWidget);
    });

    testWidgets('detail screen shows "No stack trace" when absent', (
      tester,
    ) async {
      const snapshot = StabilitySnapshot(
        errorCount: 1,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'Silent error',
            context: 'FlutterError',
            clockMicros: 1000000,
            stackTraceString: null,
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));
      await tester.tap(find.textContaining('Silent error'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No stack trace captured'), findsOneWidget);
    });

    testWidgets('detail back button returns to errors list', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 1,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'Drilldown error',
            context: 'FlutterError',
            clockMicros: 1000000,
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));
      await tester.tap(find.textContaining('Drilldown error'));
      await tester.pumpAndSettle();

      // Back
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Back on the list
      expect(find.textContaining('Drilldown error'), findsWidgets);
    });
  });

  group('StabilityView — Stalls sub-tab (empty state)', () {
    testWidgets('shows empty state when no stalls', (tester) async {
      await tester.pumpWidget(_harness(_emptySnapshot));
      await tester.tap(find.text('Stalls'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No stalls detected'), findsOneWidget);
    });

    testWidgets('header references 250ms watchdog threshold', (tester) async {
      await tester.pumpWidget(_harness(_emptySnapshot));
      await tester.tap(find.text('Stalls'));
      await tester.pumpAndSettle();

      // The threshold appears in both the header text and the empty-state sub
      // caption, so assert at least one occurrence.
      expect(find.textContaining('250ms'), findsWidgets);
    });
  });

  group('StabilityView — Stalls sub-tab (rows + color grading)', () {
    testWidgets('renders stall rows with duration', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 0,
        stallCount: 2,
        recentErrors: [],
        recentStalls: [
          StallRecord(durationMicros: 350000, clockMicros: 1000000),
          StallRecord(durationMicros: 1200000, clockMicros: 2000000),
        ],
      );

      await tester.pumpWidget(_harness(snapshot));
      await tester.tap(find.text('Stalls'));
      await tester.pumpAndSettle();

      // 350ms stall
      expect(find.textContaining('350.0ms'), findsOneWidget);
      // 1.2s stall
      expect(find.textContaining('1.20s'), findsOneWidget);
    });

    testWidgets('does NOT render a cause field (not in StallRecord)', (
      tester,
    ) async {
      // StallRecord has no cause — verify we never fabricate one.
      const snapshot = StabilitySnapshot(
        errorCount: 0,
        stallCount: 1,
        recentErrors: [],
        recentStalls: [
          StallRecord(durationMicros: 800000, clockMicros: 1000000),
        ],
      );

      await tester.pumpWidget(_harness(snapshot));
      await tester.tap(find.text('Stalls'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cause'), findsNothing);
      expect(find.textContaining('Slow layout'), findsNothing);
      expect(find.textContaining('Garbage collection'), findsNothing);
    });

    testWidgets('stall header shows stallCount from snapshot', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 0,
        stallCount: 5,
        recentErrors: [],
        recentStalls: [
          StallRecord(durationMicros: 500000, clockMicros: 1000000),
        ],
      );

      await tester.pumpWidget(_harness(snapshot));
      await tester.tap(find.text('Stalls'));
      await tester.pumpAndSettle();

      expect(find.textContaining('5 stalls'), findsOneWidget);
    });

    testWidgets('sub-second stall shown in ms; >= 1s stall shown in seconds', (
      tester,
    ) async {
      const snapshot = StabilitySnapshot(
        errorCount: 0,
        stallCount: 2,
        recentErrors: [],
        recentStalls: [
          StallRecord(durationMicros: 600000, clockMicros: 1000000),
          StallRecord(durationMicros: 2500000, clockMicros: 2000000),
        ],
      );

      await tester.pumpWidget(_harness(snapshot));
      await tester.tap(find.text('Stalls'));
      await tester.pumpAndSettle();

      expect(find.textContaining('600.0ms'), findsOneWidget);
      expect(find.textContaining('2.50s'), findsOneWidget);
    });
  });

  group('StabilityView — no overflow', () {
    testWidgets('no widget overflow errors on errors tab', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 3,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message:
                'Very long error message that might overflow '
                'if not properly ellipsized in the widget',
            context: 'FlutterError',
            clockMicros: 1000000,
          ),
          ErrorRecord(
            message: 'Short error',
            context: null,
            clockMicros: 2000000,
          ),
        ],
        recentStalls: [],
      );

      await tester.pumpWidget(_harness(snapshot));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no widget overflow errors on stalls tab', (tester) async {
      const snapshot = StabilitySnapshot(
        errorCount: 0,
        stallCount: 2,
        recentErrors: [],
        recentStalls: [
          StallRecord(durationMicros: 500000, clockMicros: 1000000),
          StallRecord(durationMicros: 1500000, clockMicros: 2000000),
        ],
      );

      await tester.pumpWidget(_harness(snapshot));
      await tester.tap(find.text('Stalls'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
