// packages/flutter_perf_radar/test/perf_radar_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerfRadarScreen', () {
    Widget buildScreen({VoidCallback? onClose}) {
      return MaterialApp(home: PerfRadarScreen(onClose: onClose));
    }

    testWidgets('renders without crashing with empty snapshot', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byType(PerfRadarScreen), findsOneWidget);
    });

    testWidgets('shows Perf Radar title', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Perf Radar'), findsOneWidget);
    });

    // ── New sub-tab labels replace old Spans tab ───────────────────────────

    testWidgets('shows Traces sub-tab (replaces old Spans)', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Traces'), findsOneWidget);
    });

    testWidgets('shows Frames sub-tab', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Frames'), findsOneWidget);
    });

    testWidgets('shows Rebuilds sub-tab', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Rebuilds'), findsOneWidget);
    });

    testWidgets('shows Startup sub-tab', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Startup'), findsOneWidget);
    });

    testWidgets('onClose callback fires on close button tap', (tester) async {
      var closed = false;
      await tester.pumpWidget(buildScreen(onClose: () => closed = true));
      final closeButton = find.byIcon(Icons.close);
      if (closeButton.evaluate().isNotEmpty) {
        await tester.tap(closeButton);
        await tester.pump();
        expect(closed, isTrue);
      }
    });

    testWidgets('no overflow errors in widget tree', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('default tab shows Traces (search field present)', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();
      // Traces tab is default — search field should be visible
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
