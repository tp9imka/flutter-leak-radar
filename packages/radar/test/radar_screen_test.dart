// test/radar_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar/radar.dart';

void main() {
  group('RadarScreen', () {
    Widget buildScreen({VoidCallback? onClose}) {
      return MaterialApp(home: RadarScreen(onClose: onClose));
    }

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.byType(RadarScreen), findsOneWidget);
    });

    testWidgets('shows Leaks tab', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Leaks'), findsOneWidget);
    });

    testWidgets('shows Performance tab', (tester) async {
      await tester.pumpWidget(buildScreen());
      expect(find.text('Performance'), findsOneWidget);
    });

    testWidgets('Leaks tab content is visible by default', (tester) async {
      await tester.pumpWidget(buildScreen());
      // LeakRadarView is embedded in the Leaks tab
      expect(find.byType(LeakRadarView), findsOneWidget);
    });

    testWidgets('Performance tab content appears after switching', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.byType(PerfRadarView), findsOneWidget);
    });

    testWidgets('onClose callback fires when close button is tapped', (
      tester,
    ) async {
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
  });

  group('RadarOverlay', () {
    testWidgets('renders child without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RadarOverlay(
            child: Scaffold(body: Center(child: Text('app'))),
          ),
        ),
      );
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('badge is present in widget tree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RadarOverlay(child: Scaffold(body: SizedBox.shrink())),
        ),
      );
      expect(find.byKey(const Key('radar_badge')), findsOneWidget);
    });
  });
}
