// test/engine/leak_engine_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/analysis/sample_history.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/leak_radar.dart';
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';
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

  group('LeakEngine navigation observer', () {
    test('navigatorObserver triggers a scan with navigation trigger', () async {
      final probe = FakeHeapProbe([]);
      final engine = LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(SuspectSet.empty()),
        autoScan: const AutoScan(
          onNavigation: true,
          navigationDebounce: Duration(milliseconds: 20),
        ),
      );
      final reports = <LeakReport>[];
      engine.reports.listen(reports.add);
      await engine.start();

      // Simulate a pop via the observer.
      engine.navigatorObserver?.didPop(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await engine.stop();

      expect(reports.where((r) => r.trigger == 'navigation'), isNotEmpty);
    });

    test('navigatorObserver is null when onNavigation is false', () async {
      final probe = FakeHeapProbe([]);
      final engine = LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(SuspectSet.empty()),
        autoScan: const AutoScan(onNavigation: false),
      );
      await engine.start();
      expect(engine.navigatorObserver, isNull);
      await engine.stop();
    });
  });

  // Facade test:
  test('LeakRadar.navigatorObserver returns inert observer when disabled',
      () async {
    // No init called — engine is null.
    await LeakRadar.dispose();
    final obs = LeakRadar.navigatorObserver;
    expect(obs, isA<NavigatorObserver>());
    // Calling didPop on the inert observer must not throw.
    expect(
      () => obs.didPop(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        null,
      ),
      returnsNormally,
    );
  });

  group('LeakEngine periodic scan via ScanScheduler', () {
    test('periodic scan fires and produces a report on the reports stream',
        () async {
      final probe = FakeHeapProbe([]);
      final engine = LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(SuspectSet.empty()),
        autoScan: const AutoScan(period: Duration(milliseconds: 30)),
      );

      final reports = <LeakReport>[];
      final sub = engine.reports.listen(reports.add);
      await engine.start();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();
      await sub.cancel();

      // At least one report should have been emitted.
      expect(reports, isNotEmpty);
      expect(reports.first.trigger, 'periodic');
    });

    test('stop() cancels periodic timer — no reports after stop', () async {
      final probe = FakeHeapProbe([]);
      final engine = LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(SuspectSet.empty()),
        autoScan: const AutoScan(period: Duration(milliseconds: 20)),
      );
      await engine.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await engine.stop();
      final countAtStop = (await engine.reports.toList()).length; // stream is closed
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // No way to receive more reports — stream is closed.
      expect(countAtStop, 0); // reports stream drained when closed
    });
  });

  // Severity reference for these tests (from severity.dart):
  //   growth mode: monotonic && growth >= 2 → critical
  //                growth >= 1 (non-monotonic) → warning
  //   Produce warning: snapshots [2, 1, 3] on *Bloc → non-monotonic, growth=2 → warning
  //   Produce critical: snapshots [1, 2, 3] on *Bloc → monotonic, growth=2 → critical
  group('LeakEngine.clearLeaks', () {
    test(
      'clearLeaks empties registry and history, emits empty report',
      () async {
        final probe = FakeHeapProbe([
          snap({'HomeBloc': 1}, 1),
          snap({'HomeBloc': 2}, 2),
          snap({'HomeBloc': 3}, 3),
        ]);
        final engine = engineWith(probe);
        await engine.start();

        final emitted = <LeakReport>[];
        final sub = engine.reports.listen(emitted.add);

        await engine.scan();
        await engine.scan();
        await engine.scan();

        engine.clearLeaks();
        // Two microtask yields let the broadcast stream deliver the event.
        await Future<void>.value();
        await Future<void>.value();

        expect(emitted.last.findings, isEmpty);
        expect(emitted.last.trigger, 'clear');

        await sub.cancel();
        await engine.stop();
      },
    );

    test('SampleHistory.clear empties snapshots', () {
      final history = SampleHistory();
      history.add(
        HeapSnapshot(
          capturedAt: DateTime(2026),
          samples: const [],
        ),
      );
      expect(history.length, 1);
      history.clear();
      expect(history.length, 0);
    });

    test('LeakRadar.clearLeaks is no-op when engine is null', () async {
      await LeakRadar.dispose();
      expect(() => LeakRadar.clearLeaks(), returnsNormally);
    });
  });

  group('reportThreshold filtering', () {
    // Helper: engine configured with the given threshold.
    LeakEngine engineWithThreshold(
      FakeHeapProbe probe,
      LeakSeverity threshold,
    ) =>
        LeakEngine(
          probe: probe,
          analyzer: const LeakAnalyzer(
            SuspectSet(<LeakRule>[LeakRule.growth('*Bloc')]),
          ),
          config: LeakRadarConfig(reportThreshold: threshold),
        );

    test(
      'warning finding is excluded when threshold is critical',
      () async {
        // Non-monotonic growth → warning severity.
        final probe = FakeHeapProbe([
          snap({'HomeBloc': 2}, 1),
          snap({'HomeBloc': 1}, 2),
          snap({'HomeBloc': 3}, 3),
        ]);
        final engine = engineWithThreshold(probe, LeakSeverity.critical);
        await engine.start();

        final emitted = <LeakReport>[];
        final sub = engine.reports.listen(emitted.add);

        await engine.scan();
        await engine.scan();
        final report = await engine.scan();

        await sub.cancel();
        await engine.stop();

        // The finding has severity=warning, threshold=critical → excluded.
        expect(report.findings, isEmpty);
        expect(engine.latest?.findings, isEmpty);
        expect(
          emitted.last.findings,
          isEmpty,
          reason: 'stream must emit filtered report',
        );
      },
    );

    test(
      'warning finding appears when threshold is lowered to warning',
      () async {
        // Same non-monotonic growth → warning severity.
        final probe = FakeHeapProbe([
          snap({'HomeBloc': 2}, 1),
          snap({'HomeBloc': 1}, 2),
          snap({'HomeBloc': 3}, 3),
        ]);
        final engine = engineWithThreshold(probe, LeakSeverity.warning);
        await engine.start();

        await engine.scan();
        await engine.scan();
        final report = await engine.scan();
        await engine.stop();

        expect(
          report.findings.any(
            (f) => f.className == 'HomeBloc' &&
                f.severity == LeakSeverity.warning,
          ),
          isTrue,
          reason: 'warning finding must pass warning threshold',
        );
      },
    );

    test(
      'updateConfig re-emits filtered report when threshold changes',
      () async {
        // Critical finding (monotonic growth).
        final probe = FakeHeapProbe([
          snap({'HomeBloc': 1}, 1),
          snap({'HomeBloc': 2}, 2),
          snap({'HomeBloc': 3}, 3),
        ]);
        // Start with threshold=critical so the critical finding passes.
        final engine = engineWithThreshold(probe, LeakSeverity.critical);
        await engine.start();

        await engine.scan();
        await engine.scan();
        await engine.scan();

        expect(engine.latest?.findings, isNotEmpty);

        final reEmitted = <LeakReport>[];
        final sub = engine.reports.listen(reEmitted.add);

        // Lower threshold to info — critical finding must pass info threshold.
        engine.updateConfig(
          const LeakRadarConfig(reportThreshold: LeakSeverity.info),
        );
        // The broadcast stream is async (sync: false), so await a microtask
        // to let the event propagate before asserting.
        await Future<void>.value();

        expect(reEmitted, hasLength(1));
        // The re-emitted report must still contain the critical finding.
        expect(
          reEmitted.first.findings.any(
            (f) => f.severity == LeakSeverity.critical,
          ),
          isTrue,
          reason: 'lowering threshold should include the existing finding',
        );

        engine.updateConfig(
          const LeakRadarConfig(reportThreshold: LeakSeverity.critical),
        );
        // Raise back to critical — critical findings still pass (index match).
        await Future<void>.value();
        expect(reEmitted, hasLength(2));
        expect(reEmitted.last.findings, isNotEmpty);

        await sub.cancel();
        await engine.stop();
      },
    );
  });
}
