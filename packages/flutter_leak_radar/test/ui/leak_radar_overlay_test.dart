// test/ui/leak_radar_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';
import 'package:flutter_leak_radar/src/leak_radar.dart';
import 'package:flutter_leak_radar/src/ui/leak_radar_overlay.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/model/leak_finding.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';

void main() {
  group('LeakRadarOverlay', () {
    testWidgets('renders child unchanged when hidden', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LeakRadarOverlay(show: false, child: const Text('content')),
        ),
      );
      expect(find.text('content'), findsOneWidget);
      expect(find.byKey(const Key('leak_radar_badge')), findsNothing);
    });

    testWidgets('badge is visible when show:true and a report is supplied', (
      tester,
    ) async {
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
      // New badge shows "1 leaks" text.
      expect(find.text('1 leaks'), findsOneWidget);
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

    testWidgets('badge is present and shows critical finding count', (
      tester,
    ) async {
      // The new badge uses rgba overlay colours, not a single container color.
      // Verify the badge renders and shows the correct count text instead.
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

      expect(find.byKey(const Key('leak_radar_badge')), findsOneWidget);
      // Badge shows count "1 leaks".
      expect(find.text('1 leaks'), findsOneWidget);
    });

    testWidgets('toggling showOverlay off hides badge on a mounted overlay', (
      tester,
    ) async {
      // LeakRadar.updateConfig updates _configNotifier even without an engine.
      await LeakRadar.dispose();
      LeakRadar.updateConfig(const LeakRadarConfig(showOverlay: true));

      final report = LeakReport(
        findings: [
          const LeakFinding(
            className: 'HomeBloc',
            kind: LeakKind.growth,
            severity: LeakSeverity.critical,
            liveCount: 2,
            growth: 1,
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
            child: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('leak_radar_badge')), findsOneWidget);

      LeakRadar.updateConfig(const LeakRadarConfig(showOverlay: false));
      await tester.pump();

      expect(find.byKey(const Key('leak_radar_badge')), findsNothing);

      // Restore default state so other tests are unaffected.
      await LeakRadar.dispose();
    });

    testWidgets('toggling showOverlay on shows badge on a mounted overlay', (
      tester,
    ) async {
      await LeakRadar.dispose();
      LeakRadar.updateConfig(const LeakRadarConfig(showOverlay: false));

      final report = LeakReport(
        findings: [
          const LeakFinding(
            className: 'HomeBloc',
            kind: LeakKind.growth,
            severity: LeakSeverity.warning,
            liveCount: 1,
            growth: 1,
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
            child: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('leak_radar_badge')), findsNothing);

      LeakRadar.updateConfig(const LeakRadarConfig(showOverlay: true));
      await tester.pump();

      expect(find.byKey(const Key('leak_radar_badge')), findsOneWidget);

      await LeakRadar.dispose();
    });

    testWidgets('pulse ring is NOT rendered when animations are disabled', (
      tester,
    ) async {
      final report = LeakReport(
        findings: [
          const LeakFinding(
            className: 'HomeBloc',
            kind: LeakKind.growth,
            severity: LeakSeverity.critical,
            liveCount: 2,
            growth: 1,
          ),
        ],
        capturedAt: DateTime.now(),
        trigger: 'manual',
        status: LeakRadarStatus.active,
      );

      // Wrap with MediaQuery that disables animations.
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: LeakRadarOverlay(
              show: true,
              initialReport: report,
              child: const Scaffold(body: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pump();

      // The badge must still be visible.
      expect(find.byKey(const Key('leak_radar_badge')), findsOneWidget);

      // When animations are disabled the pulse AnimatedBuilder is not rendered.
      expect(find.byKey(const Key('leak_radar_pulse')), findsNothing);
    });
  });

  group('LeakRadarOverlay above MaterialApp (real-usage shape)', () {
    testWidgets(
      'renders without exception above MaterialApp (real-usage shape)',
      (tester) async {
        await tester.pumpWidget(
          LeakRadarOverlay(
            show: true,
            initialReport: LeakReport(
              findings: const [],
              capturedAt: DateTime.now(),
              trigger: 'test',
              status: LeakRadarStatus.active,
            ),
            child: MaterialApp(home: Scaffold(body: Text('app'))),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('leak_radar_badge')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tapping badge opens LeakRadarScreen above MaterialApp', (
      tester,
    ) async {
      await tester.pumpWidget(
        LeakRadarOverlay(
          show: true,
          initialReport: LeakReport(
            findings: const [],
            capturedAt: DateTime.now(),
            trigger: 'test',
            status: LeakRadarStatus.active,
          ),
          child: MaterialApp(home: Scaffold(body: Text('app'))),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('leak_radar_badge')));
      await tester.pumpAndSettle();

      expect(find.text('Leak Radar'), findsOneWidget);
    });

    testWidgets('inspector closes when onClose is triggered', (tester) async {
      await tester.pumpWidget(
        LeakRadarOverlay(
          show: true,
          initialReport: LeakReport(
            findings: const [],
            capturedAt: DateTime.now(),
            trigger: 'test',
            status: LeakRadarStatus.active,
          ),
          child: MaterialApp(home: Scaffold(body: Text('app'))),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('leak_radar_badge')));
      await tester.pumpAndSettle();

      expect(find.text('Leak Radar'), findsOneWidget);

      // Close via the leading close button.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leak_radar_badge')), findsOneWidget);
      expect(find.text('Leak Radar'), findsNothing);
    });
  });
}
