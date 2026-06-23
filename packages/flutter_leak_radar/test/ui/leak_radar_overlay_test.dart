// test/ui/leak_radar_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/ui/leak_radar_overlay.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/model/leak_finding.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';

void main() {
  group('LeakRadarOverlay', () {
    testWidgets('renders child unchanged when hidden', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(
            show: false,
            child: const Text('content'),
          ),
        ),
      );
      expect(find.text('content'), findsOneWidget);
      expect(find.byKey(const Key('leak_radar_badge')), findsNothing);
    });

    testWidgets('badge is visible when show:true and a report is supplied', (tester) async {
      final report = LeakReport(
        findings: [
          const LeakFinding(
            className: 'HomeBloc',
            kind: LeakKind.growth,
            severity: LeakSeverity.critical,
            liveCount: 3,
            growth: 2,
          ),
        ],
        capturedAt: DateTime.now(),
        trigger: 'manual',
        status: LeakRadarStatus.active,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(
            show: true,
            initialReport: report,
            child: const Scaffold(body: Text('content')),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('leak_radar_badge')), findsOneWidget);
      // Count text shows 1 finding.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('tapping badge navigates to LeakRadarScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(
            show: true,
            initialReport: LeakReport(
              findings: const [],
              capturedAt: DateTime.now(),
              trigger: 'manual',
              status: LeakRadarStatus.active,
            ),
            child: const Scaffold(body: Text('content')),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('leak_radar_badge')));
      await tester.pumpAndSettle();

      expect(find.text('Leak Radar'), findsOneWidget); // AppBar title
    });

    testWidgets('badge color reflects worst severity', (tester) async {
      // critical → red; warning → orange; info → blue
      final criticalReport = LeakReport(
        findings: [
          const LeakFinding(
            className: 'X',
            kind: LeakKind.notGced,
            severity: LeakSeverity.critical,
            liveCount: 1,
            growth: 0,
          ),
        ],
        capturedAt: DateTime.now(),
        trigger: 'manual',
        status: LeakRadarStatus.active,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(
            show: true,
            initialReport: criticalReport,
            child: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();

      // Find the badge container and check its color.
      final badge = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('leak_radar_badge')),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = badge.decoration as BoxDecoration;
      expect(decoration.color, Colors.red);
    });
  });
}
