// test/leak_radar_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_heap_probe.dart';

void main() {
  tearDown(() => LeakRadar.dispose());

  test('disabled config -> status disabled and scan returns a disabled report', () async {
    await LeakRadar.init(const LeakRadarConfig(enabled: false));
    expect(LeakRadar.status, LeakRadarStatus.disabled);
    final report = await LeakRadar.scan();
    expect(report.status, LeakRadarStatus.disabled);
    expect(report.findings, isEmpty);
  });

  test('track/markDisposed never throw when disabled', () async {
    await LeakRadar.init(const LeakRadarConfig(enabled: false));
    final o = Object();
    LeakRadar.track(o, tag: 'x'); // no-op, no throw
    LeakRadar.markDisposed(o);
    expect(LeakRadar.latest, isNull);
  });

  test('debugInstall wires a fake engine and scan reports findings', () async {
    final probe = FakeHeapProbe([
      HeapSnapshot(capturedAt: DateTime(2026), samples: [ClassSample(className: 'HomeBloc', instancesCurrent: 5, bytesCurrent: 0, timestamp: DateTime(2026))]),
    ]);
    final engine = LeakEngine(probe: probe, analyzer: const LeakAnalyzer(SuspectSet.empty()));
    await LeakRadar.debugInstall(engine);
    final report = await LeakRadar.scan();
    expect(report.status, LeakRadarStatus.active);
  });

  group('LeakRadar.overlay()', () {
    testWidgets('returns child unchanged when not initialized', (tester) async {
      const key = Key('child');
      const child = SizedBox(key: key);

      final result = LeakRadar.overlay(child: child);

      // When disabled, the same widget instance should be returned.
      expect(result, same(child));
    });

    testWidgets('wraps child in LeakRadarOverlay when enabled and showOverlay:true', (tester) async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );

      const child = SizedBox();
      final overlaid = LeakRadar.overlay(child: child);
      expect(overlaid, isA<LeakRadarOverlay>());

      await LeakRadar.dispose();
    });
  });
}
