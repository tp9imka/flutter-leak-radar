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

    testWidgets('renders the More overflow menu button', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();
      // Heap snapshot is now in a popup menu accessed via the More button.
      expect(find.byTooltip('More'), findsOneWidget);
    });

    testWidgets('opening popup shows Collect heap snapshot item',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      // Open the overflow popup.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      expect(find.textContaining('heap snapshot'), findsOneWidget);
    });

    testWidgets('heap snapshot menu item tap does not throw', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.textContaining('heap snapshot'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('heap snapshot menu item tap shows a SnackBar', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
      await tester.pump();

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.textContaining('heap snapshot'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pumpAndSettle();

      // Expect either the success or the unavailable snackbar.
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
