import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import 'fakes.dart';

RadarSession _session() {
  final connection = FakeRadarConnection();
  return RadarSession(
    connection: connection,
    memory: MemoryController(
      snapshotSource: FakeSnapshotSource(),
      connection: connection,
    ),
    perf: PerfDataController(),
    exporter: RecordingExporter(),
  );
}

void main() {
  tearDown(RadarSession.debugReset);

  testWidgets('main scaffold shows a banner when the store refuses a restore', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = InMemorySnapshotStore()
      ..restoreRefusal = 'Session schema v3 is newer than this build supports.';
    RadarSession.install(_session());
    await RadarSession.instance.attachStore(store);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1280,
            height: 800,
            child: LeakRadarMainScaffold(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(RadarBanner), findsOneWidget);
    expect(find.textContaining('newer than this build'), findsOneWidget);
    expect(find.text('Start new'), findsOneWidget);

    // Dismissing clears the refusal and removes the banner.
    await tester.tap(find.text('Start new'));
    await tester.pumpAndSettle();
    expect(find.byType(RadarBanner), findsNothing);
  });
}
