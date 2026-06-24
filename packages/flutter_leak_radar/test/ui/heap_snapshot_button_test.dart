// test/ui/heap_snapshot_button_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(LeakRadar.dispose);

  group('LeakRadarScreen — Collect heap snapshot button', () {
    setUp(() async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
    });

    testWidgets('renders the Collect heap snapshot button', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();
      expect(find.byTooltip('Collect heap snapshot'), findsOneWidget);
      expect(find.byIcon(Icons.memory), findsOneWidget);
    });

    testWidgets('button tap does not throw', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Collect heap snapshot'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('button tap shows a SnackBar', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Collect heap snapshot'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pumpAndSettle();

      // Expect either the success or the unavailable snackbar.
      final snackBars = find.byType(SnackBar);
      expect(snackBars, findsOneWidget);
    });
  });
}
