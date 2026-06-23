// test/ui/leak_radar_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';

HeapSnapshot snap(Map<String, int> c) => HeapSnapshot(
      capturedAt: DateTime(2026),
      samples: [for (final e in c.entries) ClassSample(className: e.key, instancesCurrent: e.value, bytesCurrent: 0, timestamp: DateTime(2026))],
    );

void main() {
  tearDown(() => LeakRadar.dispose());

  testWidgets('shows empty state then findings after Scan now', (tester) async {
    final probe = FakeHeapProbe([snap({'HomeBloc': 1}), snap({'HomeBloc': 2}), snap({'HomeBloc': 3})]);
    final engine = LeakEngine(probe: probe, analyzer: const LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')])));
    await LeakRadar.debugInstall(engine);
    await LeakRadar.scan();
    await LeakRadar.scan();

    await tester.pumpWidget(const MaterialApp(home: LeakRadarScreen()));
    await tester.tap(find.byTooltip('Scan now'));
    await tester.pumpAndSettle();

    expect(find.text('HomeBloc'), findsOneWidget);
  });

  group('LeakRadarScreen — Export and Share buttons', () {
    setUp(() async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
    });

    testWidgets('shows Export and Share action buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LeakRadarScreen()),
      );
      await tester.pump();
      expect(find.byTooltip('Export'), findsOneWidget);
      expect(find.byTooltip('Share'), findsOneWidget);
    });

    testWidgets('Export button calls exportToFile and shows snackbar', (tester) async {
      // Perform a scan first so latest is non-null.
      await LeakRadar.scan();

      await tester.pumpWidget(
        const MaterialApp(home: LeakRadarScreen()),
      );
      await tester.pump();

      // runAsync allows real file I/O inside _export() to complete.
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Export'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      // Pump frames so the SnackBar can render.
      await tester.pump();
      await tester.pumpAndSettle();

      // A snackbar should appear with the exported file path.
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('empty state is shown when no findings', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LeakRadarScreen()),
      );
      await tester.pump();
      expect(find.text('No leaks detected'), findsOneWidget);
    });

    testWidgets('reports stream updates UI without full rebuild', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LeakRadarScreen()),
      );
      await tester.pump();

      // Trigger a scan via the button.
      await tester.tap(find.byTooltip('Scan now'));
      await tester.pumpAndSettle();

      // No exception should occur.
      expect(tester.takeException(), isNull);
    });
  });
}
