// test/ui/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';
import 'package:flutter_leak_radar/src/leak_radar.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/ui/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';
import '../engine/leak_engine_test.dart' show engineWith;

Widget _wrap(Widget child) => MaterialApp(home: child);

// Seeds the engine and a known starting config so every test starts from
// the same state.
Future<void> _setup([LeakRadarConfig config = const LeakRadarConfig()]) async {
  final probe = FakeHeapProbe([]);
  final engine = engineWith(probe);
  await LeakRadar.debugInstall(engine);
  LeakRadar.updateConfig(config);
}

void main() {
  tearDown(() async => LeakRadar.dispose());

  testWidgets('smoke — SettingsScreen builds without error', (tester) async {
    await _setup();
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('OVERLAY'), findsOneWidget);
    expect(find.text('REPORT THRESHOLD'), findsOneWidget);
    expect(find.text('AUTO-SCAN'), findsOneWidget);
    expect(find.text('PRECISION'), findsOneWidget);
  });

  testWidgets('overlay toggle disables showOverlay in config', (tester) async {
    await _setup(const LeakRadarConfig(showOverlay: true));
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pump();

    expect(LeakRadar.configListenable.value.showOverlay, isTrue);

    await tester.tap(
      find.byKey(const Key('settings_overlay_toggle')),
    );
    await tester.pump();

    expect(LeakRadar.configListenable.value.showOverlay, isFalse);
  });

  testWidgets('tapping Info segment sets reportThreshold to info',
      (tester) async {
    await _setup(
      const LeakRadarConfig(reportThreshold: LeakSeverity.warning),
    );
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pump();

    await tester.tap(find.text('Info'));
    await tester.pump();

    expect(
      LeakRadar.configListenable.value.reportThreshold,
      LeakSeverity.info,
    );
  });

  testWidgets('tapping Critical segment sets reportThreshold to critical',
      (tester) async {
    await _setup();
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pump();

    await tester.tap(find.text('Critical'));
    await tester.pump();

    expect(
      LeakRadar.configListenable.value.reportThreshold,
      LeakSeverity.critical,
    );
  });

  testWidgets('tapping Periodic · 30 s row updates autoScan', (tester) async {
    await _setup();
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pump();

    await tester.tap(find.text('Periodic · 30 s'));
    await tester.pump();

    final autoScan = LeakRadar.configListenable.value.autoScan;
    expect(autoScan.hasPeriodic, isTrue);
    expect(autoScan.period, const Duration(seconds: 30));

    // Stop the periodic timer before the test framework checks for pending timers.
    await LeakRadar.dispose();
  });

  testWidgets('tapping On screen-pop row updates autoScan.onNavigation',
      (tester) async {
    await _setup();
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pump();

    await tester.tap(find.text('On screen-pop'));
    await tester.pump();

    expect(
      LeakRadar.configListenable.value.autoScan.onNavigation,
      isTrue,
    );
  });

  testWidgets('precision toggle disables preciseTracking', (tester) async {
    await _setup(const LeakRadarConfig(preciseTracking: true));
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pump();

    expect(LeakRadar.configListenable.value.preciseTracking, isTrue);

    // Scroll the precision toggle into view before tapping.
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_precision_toggle')),
      100,
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('settings_precision_toggle')),
    );
    await tester.pump();

    expect(LeakRadar.configListenable.value.preciseTracking, isFalse);
  });

  testWidgets('RECOMMENDED tag visible for On screen-pop option',
      (tester) async {
    await _setup();
    await tester.pumpWidget(_wrap(const SettingsScreen()));
    await tester.pump();
    expect(find.text('RECOMMENDED'), findsOneWidget);
  });
}
