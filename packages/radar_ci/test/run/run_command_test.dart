import 'package:radar_ci/radar_ci.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../support/fake_vm_service.dart';

const int _second = 1000000;

/// Virtual clock: [delay] advances now instantly so the full cadence runs
/// without real waiting, and sample timestamps are exactly start + offset.
final class _FakeClock implements RunClock {
  _FakeClock(this._now);
  int _now;

  @override
  int nowMicros() => _now;

  @override
  Future<void> delay(Duration duration) async {
    if (duration > Duration.zero) _now += duration.inMicroseconds;
  }
}

/// One isolate; heap grows by [growthPerCall] bytes on each getMemoryUsage so
/// the produced series is realistic. Records allocation profiles for
/// checkpoints.
class _GrowingFakeService extends FakeVmService {
  static const int _growthPerCall = 1000;
  int _heap = 100000;

  @override
  Future<VM> getVM() async => VM(isolates: [IsolateRef(id: 'isolates/main')]);

  @override
  Future<MemoryUsage> getMemoryUsage(String isolateId) async {
    _heap += _growthPerCall;
    return MemoryUsage(
      heapUsage: _heap,
      heapCapacity: _heap * 2,
      externalUsage: 500,
    );
  }

  @override
  Future<ProcessMemoryUsage> getProcessMemoryUsage() async =>
      ProcessMemoryUsage(
        root: ProcessMemoryItem(name: 'Total', size: _heap * 3),
      );

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? reset,
    bool? gc,
  }) async => AllocationProfile()
    ..members = [
      ClassHeapStats(
        classRef: ClassRef(id: 'c/String', name: 'String'),
        bytesCurrent: 4000,
        instancesCurrent: 90,
      ),
    ];
}

/// Samples succeed, but every allocation-profile RPC throws — so only the
/// per-checkpoint capture degrades, never the sampling.
class _AllocThrowFakeService extends FakeVmService {
  int _heap = 100000;

  @override
  Future<VM> getVM() async => VM(isolates: [IsolateRef(id: 'isolates/main')]);

  @override
  Future<MemoryUsage> getMemoryUsage(String isolateId) async {
    _heap += 1000;
    return MemoryUsage(
      heapUsage: _heap,
      heapCapacity: _heap * 2,
      externalUsage: 0,
    );
  }

  @override
  Future<ProcessMemoryUsage> getProcessMemoryUsage() async =>
      ProcessMemoryUsage(
        root: ProcessMemoryItem(name: 'Total', size: _heap),
      );

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? reset,
    bool? gc,
  }) => Future.error(StateError('profile RPC down'));
}

/// Advances virtual time, then throws on the [explodeAfter]-th delay to model
/// an unexpected mid-run failure the loop cannot foresee.
final class _ExplodingClock implements RunClock {
  _ExplodingClock({required this.explodeAfter});
  final int explodeAfter;
  int _now = 0;
  int _delays = 0;

  @override
  int nowMicros() => _now;

  @override
  Future<void> delay(Duration duration) async {
    if (_delays++ >= explodeAfter) throw StateError('clock exploded');
    if (duration > Duration.zero) _now += duration.inMicroseconds;
  }
}

/// A native co-sampler over canned readings: nativePssKb grows and threads
/// holds, except on the tick indices in [goneTicks], which read pid-gone (every
/// column unmeasured) — the honest gap the run must fold in without touching
/// the Dart lane.
final class _FakeNativeCoSampler implements NativeCoSampler {
  _FakeNativeCoSampler({this.goneTicks = const {}});

  final Set<int> goneTicks;
  int _tick = 0;
  int _pss = 100;

  static const Set<TriageColumn> _columns = {
    TriageColumn.nativePssKb,
    TriageColumn.threads,
  };

  @override
  Future<Map<TriageColumn, SampleValue>> sampleAt(int tMicros) async {
    final index = _tick++;
    if (goneTicks.contains(index)) {
      return allUnmeasured(_columns, 'process not running');
    }
    _pss += 10;
    return {
      TriageColumn.nativePssKb: SampleValue.measured(_pss),
      TriageColumn.threads: const SampleValue.measured(24),
    };
  }
}

NativeCoDrive _coDrive(
  RunClock clock, {
  Set<int> goneTicks = const {},
  int intervalSeconds = 10,
}) => NativeCoDrive(
  intervalMicros: intervalSeconds * _second,
  sampler: _FakeNativeCoSampler(goneTicks: goneTicks),
  builder: TimelineBuilder(nowMicros: clock.nowMicros),
);

RunConfig _config({
  int durationSeconds = 120,
  int intervalSeconds = 5,
  int settleSeconds = 30,
  int checkpoints = 3,
  int snapshotEvery = 0,
}) => RunConfig(
  durationMicros: durationSeconds * _second,
  sampleIntervalMicros: intervalSeconds * _second,
  settleMicros: settleSeconds * _second,
  checkpointCount: checkpoints,
  snapshotEvery: snapshotEvery,
  allocationTopN: 10,
  outPath: 'run.json',
  projectPackages: const ['app'],
  projectPackagesSource: 'flag',
);

RunMetadata _metadata() => RunMetadata(startedAt: DateTime.utc(2026));

void main() {
  group('executeRun', () {
    test('builds the four series and start..end checkpoints', () async {
      final doc = await executeRun(
        service: _GrowingFakeService(),
        clock: _FakeClock(1000000000),
        config: _config(),
        metadata: _metadata(),
      );

      expect(doc.series.map((s) => s.name).toSet(), {
        'dart.heap.used',
        'dart.heap.capacity',
        'dart.external',
        'process.rss',
      });
      expect(doc.checkpoints.map((c) => c.label).toList(), [
        'start',
        'cp1',
        'cp2',
        'cp3',
        'end',
      ]);
      // 120s / 5s + 1 = 25 samples across the run.
      final heapUsed = doc.series.firstWhere((s) => s.name == 'dart.heap.used');
      expect(heapUsed.samples, hasLength(25));
      // Post-settle (>= 30s) samples clear the assessment floor.
      final postSettle = heapUsed.samples.where(
        (s) => s.tMicros >= 1000000000 + 30 * _second,
      );
      expect(postSettle.length, greaterThanOrEqualTo(12));
      // Allocation profile captured at checkpoints.
      expect(doc.checkpoints.first.allocationTopN['String'], 90);
    });

    test(
      'fires the driver hook between checkpoints, never after the last',
      () async {
        final log = <String>[];
        await executeRun(
          service: _GrowingFakeService(),
          clock: _FakeClock(0),
          config: _config(checkpoints: 1),
          metadata: _metadata(),
          onCheckpoint: (cp, _) async => log.add('checkpoint:${cp.label}'),
          driverHook: () async => log.add('hook'),
        );

        final checkpoints = log
            .where((e) => e.startsWith('checkpoint:'))
            .toList();
        final hooks = log.where((e) => e == 'hook').toList();
        // start, cp1, end -> 3 checkpoints, hook after the first two only.
        expect(checkpoints, [
          'checkpoint:start',
          'checkpoint:cp1',
          'checkpoint:end',
        ]);
        expect(hooks, hasLength(2));
        // A hook always sits between two checkpoints, and none trails 'end'.
        expect(log.last, 'checkpoint:end');
        expect(log, [
          'checkpoint:start',
          'hook',
          'checkpoint:cp1',
          'hook',
          'checkpoint:end',
        ]);
      },
    );

    test(
      'warns once when the cadence cannot reach an assessable sample count',
      () async {
        final warnings = <String>[];
        await executeRun(
          service: _GrowingFakeService(),
          clock: _FakeClock(0),
          // 60s duration, 5s interval, 30s settle -> 7 post-settle samples.
          config: _config(durationSeconds: 60),
          metadata: _metadata(),
          warn: warnings.add,
        );
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('assess'));
      },
    );

    test('does not warn for the shipped defaults', () async {
      final warnings = <String>[];
      await executeRun(
        service: _GrowingFakeService(),
        clock: _FakeClock(0),
        config: _config(durationSeconds: 180, intervalSeconds: 5),
        metadata: _metadata(),
        warn: warnings.add,
      );
      expect(warnings, isEmpty);
    });
  });

  group('executeRun — native co-drive', () {
    test('folds a native timeline whose gaps are independent of the Dart '
        'lane', () async {
      final clock = _FakeClock(0);
      final doc = await executeRun(
        service: _GrowingFakeService(),
        clock: clock,
        config: _config(durationSeconds: 120, intervalSeconds: 5),
        metadata: _metadata(),
        // Native ticks at 0,10,…,120 (13 ticks); tick #2 (t=20s) reads pid-gone.
        progress: RunProgress(nativeCoDrive: _coDrive(clock, goneTicks: {2})),
      );

      final native = doc.nativeTimeline;
      expect(native, isNotNull);
      final pss = native!.columns[TriageColumn.nativePssKb]!;
      // 13 ticks minus the one pid-gone tick = 12 measured samples.
      expect(pss.samples, hasLength(12));
      expect(pss.gaps, hasLength(1));
      expect(pss.gaps.single.reason, contains('process not running'));
      // The gap sits at the native tick's instant (20s), on the native clock.
      expect(pss.gaps.single.startMicros, 20 * _second);
      // The native series carries the canonical KiB unit, so triage never
      // degrades it on a unit mismatch.
      expect(pss.unit, 'kb');

      // The Dart lane sampled straight through the native gap — 25 samples, no
      // gap — proving the lanes are independent.
      final heap = doc.series.firstWhere((s) => s.name == 'dart.heap.used');
      expect(heap.samples, hasLength(25));
      expect(heap.gaps, isEmpty);
    });

    test('marks the native timeline at each Dart checkpoint', () async {
      final clock = _FakeClock(0);
      final doc = await executeRun(
        service: _GrowingFakeService(),
        clock: clock,
        config: _config(durationSeconds: 120, intervalSeconds: 5),
        metadata: _metadata(),
        progress: RunProgress(nativeCoDrive: _coDrive(clock)),
      );

      expect(doc.nativeTimeline!.marks.map((m) => m.label).toList(), [
        'start',
        'cp1',
        'cp2',
        'cp3',
        'end',
      ]);
    });

    test('a mid-run abort keeps the native ticks gathered so far', () async {
      final clock = _ExplodingClock(explodeAfter: 5);
      final doc = await executeRun(
        service: _GrowingFakeService(),
        clock: clock,
        config: _config(),
        metadata: _metadata(),
        progress: RunProgress(nativeCoDrive: _coDrive(clock)),
      );

      expect(doc.metadata.completed, isFalse);
      final native = doc.nativeTimeline;
      expect(native, isNotNull);
      // Some native ticks landed before the clock exploded — the partial lane
      // survives the abort exactly like the Dart samples do.
      expect(native!.columns[TriageColumn.nativePssKb]!.samples, isNotEmpty);
    });
  });

  group('parseDurationMicros', () {
    test('parses s/m/h suffixes and bare seconds', () {
      expect(parseDurationMicros('30s'), 30 * _second);
      expect(parseDurationMicros('3m'), 180 * _second);
      expect(parseDurationMicros('1h'), 3600 * _second);
      expect(parseDurationMicros('45'), 45 * _second);
    });

    test('rejects malformed durations', () {
      expect(() => parseDurationMicros('soon'), throwsFormatException);
      expect(() => parseDurationMicros('-5s'), throwsFormatException);
    });
  });

  group('parseRunConfig', () {
    test('enforces the 2m minimum unless --allow-short', () {
      final parser = buildRunArgParser();
      expect(
        () => parseRunConfig(parser.parse(['--vm-uri', 'ws://x', '-d', '30s'])),
        throwsA(isA<UsageException>()),
      );
      final ok = parseRunConfig(
        parser.parse(['--vm-uri', 'ws://x', '-d', '30s', '--allow-short']),
      );
      expect(ok.durationMicros, 30 * _second);
    });

    test('defaults satisfy the assessment floor', () {
      final config = parseRunConfig(
        buildRunArgParser().parse(['--vm-uri', 'ws://x']),
      );
      expect(
        isAssessableCadence(
          durationMicros: config.durationMicros,
          sampleIntervalMicros: config.sampleIntervalMicros,
          settleMicros: config.settleMicros,
        ),
        isTrue,
      );
    });

    test('mode is null on attach unless supplied or derivable', () {
      final parser = buildRunArgParser();
      expect(parseRunConfig(parser.parse(['--vm-uri', 'ws://x'])).mode, isNull);
      expect(
        parseRunConfig(
          parser.parse(['--vm-uri', 'ws://x', '--mode', 'profile']),
        ).mode,
        'profile',
      );
      expect(
        parseRunConfig(
          parser.parse(['--cmd', 'flutter run --release -d x']),
        ).mode,
        'release',
      );
    });
  });

  group('checkpoint degradation and partial flush', () {
    test(
      'a failed checkpoint capture is marked failed; the run completes',
      () async {
        final doc = await executeRun(
          service: _AllocThrowFakeService(),
          clock: _FakeClock(0),
          config: _config(checkpoints: 1),
          metadata: _metadata(),
        );

        expect(doc.metadata.completed, isTrue);
        expect(doc.checkpoints.map((c) => c.label), ['start', 'cp1', 'end']);
        for (final cp in doc.checkpoints) {
          expect(cp.captureStatus, 'failed');
          expect(cp.allocationTopN, isEmpty);
          expect(cp.captureError, contains('profile RPC down'));
        }
        // Sampling was never interrupted by the checkpoint failures.
        final heap = doc.series.firstWhere((s) => s.name == 'dart.heap.used');
        expect(heap.samples, isNotEmpty);
      },
    );

    test(
      'an unexpected mid-run error yields a partial, non-completed document',
      () async {
        final doc = await executeRun(
          service: _GrowingFakeService(),
          clock: _ExplodingClock(explodeAfter: 5),
          config: _config(),
          metadata: _metadata(),
        );

        expect(doc.metadata.completed, isFalse);
        expect(doc.metadata.abortReason, contains('clock exploded'));
        // Everything collected before the abort survives in the partial doc.
        final heap = doc.series.firstWhere((s) => s.name == 'dart.heap.used');
        expect(heap.samples, isNotEmpty);
      },
    );
  });

  group('exitCodeForDocument', () {
    RadarRunDocument doc({required bool completed}) => RadarRunDocument(
      metadata: RunMetadata(
        startedAt: DateTime.utc(2026),
        completed: completed,
        abortReason: completed ? null : 'interrupted',
      ),
      series: const [],
      checkpoints: const [],
    );

    test('maps completion to the exit contract (0 ok / 2 tool failure)', () {
      expect(exitCodeForDocument(doc(completed: true)), 0);
      expect(exitCodeForDocument(doc(completed: false)), 2);
    });
  });

  group('resolveMode', () {
    test('an explicit mode always wins', () {
      expect(
        resolveMode(explicitMode: 'release', cmd: 'flutter run --profile'),
        'release',
      );
    });

    test('derives from the --cmd flags when no mode is supplied', () {
      expect(resolveMode(cmd: 'flutter run --profile -d x'), 'profile');
      expect(resolveMode(cmd: 'flutter run --release'), 'release');
      expect(resolveMode(cmd: 'flutter run --debug'), 'debug');
    });

    test('is null on attach with no mode and no cmd', () {
      expect(resolveMode(), isNull);
      expect(resolveMode(cmd: 'dart --enable-vm-service=0 loop.dart'), isNull);
    });
  });
}
