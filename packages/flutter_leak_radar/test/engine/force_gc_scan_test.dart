// test/engine/force_gc_scan_test.dart
//
// Regression: the precise tracker decides "notGced" from
// developer.reachabilityBarrier, which only advances on a real GC. The scan
// must force that GC, otherwise a retained, disposed, tracked object is never
// reported. Earlier this was broken — forceGc() existed but was never wired
// into the scan, and every precise test mocked the GC counter, hiding the gap.
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/precise/gc_support.dart';
import 'package:flutter_leak_radar/src/precise/leak_object_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_heap_probe.dart';

class _FakeGc implements GcCounter {
  int value = 0;
  @override
  int get currentGcCount => value;
}

class _Dummy {}

LeakEngine _engineWith(_FakeGc gc) => LeakEngine(
  // available:false → preciseOnly status, isolating the precise path (no
  // heap capture); proves precise detection works without the VM service.
  probe: FakeHeapProbe(const [], available: false),
  analyzer: LeakAnalyzer(const SuspectSet.empty()),
  registry: LeakObjectRegistry(gcCounter: gc, disposalGrace: Duration.zero),
  gcCyclesForPreciseLeak: 1,
  config: const LeakRadarConfig(preciseTracking: true),
  // Simulate forceGc advancing the reachability barrier by one cycle.
  gcForcer: () async => gc.value++,
);

void main() {
  test(
    'scan() forces a GC so a retained, disposed tracked object is notGced',
    () async {
      final gc = _FakeGc();
      final engine = _engineWith(gc);
      await engine.start();

      final leaked = _Dummy();
      engine.track(leaked, tag: 'Dummy');
      engine.markDisposed(leaked); // disposedGc = 0

      final report = await engine.scan();

      expect(
        report.findings.where(
          (f) => f.kind == LeakKind.notGced && f.tag == 'Dummy',
        ),
        isNotEmpty,
        reason:
            'scan() must force a GC so the barrier advances past disposedGc',
      );
      expect(leaked, isNotNull); // keep alive through collectLeaks
    },
  );

  test('forceGcAndScan() advances the barrier and reports notGced', () async {
    final gc = _FakeGc();
    final engine = _engineWith(gc);
    await engine.start();

    final leaked = _Dummy();
    engine.track(leaked, tag: 'Dummy');
    engine.markDisposed(leaked);

    final report = await engine.forceGcAndScan();

    expect(
      report.findings.where(
        (f) => f.kind == LeakKind.notGced && f.tag == 'Dummy',
      ),
      isNotEmpty,
    );
    expect(leaked, isNotNull);
  });
}
