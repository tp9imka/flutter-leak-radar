// test/engine/leak_engine_test.dart
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';

HeapSnapshot snap(Map<String, int> counts, int t) => HeapSnapshot(
      capturedAt: DateTime(2026, 1, 1, 0, 0, t),
      samples: [for (final e in counts.entries) ClassSample(className: e.key, instancesCurrent: e.value, bytesCurrent: 0, timestamp: DateTime(2026, 1, 1, 0, 0, t))],
    );

LeakEngine engineWith(FakeHeapProbe probe) => LeakEngine(
      probe: probe,
      analyzer: const LeakAnalyzer(SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')])),
    );

void main() {
  test('status is active when the probe is available', () async {
    final engine = engineWith(FakeHeapProbe([snap({'A': 1}, 1)]));
    await engine.start();
    expect(engine.status, LeakRadarStatus.active);
    await engine.stop();
  });

  test('status is preciseOnly when the probe is unavailable', () async {
    final engine = engineWith(FakeHeapProbe([], available: false));
    await engine.start();
    expect(engine.status, LeakRadarStatus.preciseOnly);
    await engine.stop();
  });

  test('repeated scans build history and detect growth', () async {
    final probe = FakeHeapProbe([snap({'HomeBloc': 1}, 1), snap({'HomeBloc': 2}, 2), snap({'HomeBloc': 3}, 3)]);
    final engine = engineWith(probe);
    await engine.start();
    await engine.scan();
    await engine.scan();
    final report = await engine.scan();
    final f = report.findings.firstWhere((f) => f.className == 'HomeBloc');
    expect(f.kind, LeakKind.growth);
    expect(f.liveCount, 3);
    await engine.stop();
  });

  test('overlapping scans are dropped, not queued', () async {
    final probe = FakeHeapProbe([snap({'A': 1}, 1)]);
    final engine = engineWith(probe);
    await engine.start();
    final a = engine.scan();
    final b = engine.scan(); // should be dropped while `a` is in flight
    await Future.wait([a, b]);
    expect(probe.captureCount, 1);
    await engine.stop();
  });

  test('reports stream emits each scan', () async {
    final probe = FakeHeapProbe([snap({'A': 1}, 1)]);
    final engine = engineWith(probe);
    await engine.start();
    final future = engine.reports.first;
    await engine.scan();
    expect((await future).trigger, 'manual');
    await engine.stop();
  });

  test('scan after stop returns disabled report without capturing', () async {
    final probe = FakeHeapProbe([snap({'A': 1}, 1)]);
    final engine = engineWith(probe);
    await engine.start();
    await engine.stop();
    final captureCountBeforeScan = probe.captureCount;
    final report = await engine.scan();
    expect(report.status, LeakRadarStatus.disabled);
    expect(probe.captureCount, captureCountBeforeScan);
  });
}
