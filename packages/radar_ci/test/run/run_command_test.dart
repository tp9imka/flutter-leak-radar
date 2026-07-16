import 'package:radar_ci/radar_ci.dart';
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
  });
}
