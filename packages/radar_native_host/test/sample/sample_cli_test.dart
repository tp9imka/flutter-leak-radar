import 'dart:async';
import 'dart:io';

import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'overnight_test_support.dart';

/// An [AdbRunner] whose [hungCall]-th probe returns a never-completing future
/// (a wedged `adb shell`); every other call resolves [pid].
final class _HangingAdb implements AdbRunner {
  _HangingAdb({required this.hungCall, required this.hung, required this.pid});
  final int hungCall;
  final Future<AdbResult> hung;
  final int pid;
  int calls = 0;

  @override
  Future<AdbResult> run(List<String> args, {String? serial, String? stdin}) {
    final call = calls++;
    return call == hungCall ? hung : Future<AdbResult>.value(pidResult(pid));
  }
}

void main() {
  late Directory tempDir;
  late String dir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sample_cli_test_');
    dir = tempDir.path;
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  List<String> baseArgs({
    String interval = '5s',
    String duration = '20s',
    String flushEvery = '60s',
  }) => [
    '--package',
    'com.example.app',
    '--out',
    dir,
    '--interval',
    interval,
    '--duration',
    duration,
    '--flush-every',
    flushEvery,
  ];

  Future<int> run(
    List<String> args, {
    required AdbRunner adb,
    required FakeClock clock,
    required FakeSampler sampler,
    Stream<ProcessSignal>? interrupts,
    StringSink? err,
  }) => runSample(
    args,
    adb: adb,
    clock: clock,
    buildSampler: (_, _) => sampler,
    lock: FakeSessionLock(),
    interrupts: interrupts ?? noInterrupts(),
    now: () => DateTime.utc(2026, 7, 17, 3),
    out: StringBuffer(),
    err: err ?? StringBuffer(),
  );

  group('parseSampleArgs', () {
    test('applies overnight defaults', () {
      final parsed = parseSampleArgs(['--package', 'p', '--out', 'd']);
      expect(parsed.interval, const Duration(seconds: 5));
      expect(parsed.duration, const Duration(hours: 8));
      expect(parsed.flushEvery, const Duration(seconds: 60));
      expect(parsed.serial, isNull);
    });

    test('falls back to ANDROID_SERIAL for --device', () {
      final parsed = parseSampleArgs(
        ['--package', 'p', '--out', 'd'],
        env: const {'ANDROID_SERIAL': 'ZY22'},
      );
      expect(parsed.serial, 'ZY22');
    });

    test('an explicit --device wins over the env', () {
      final parsed = parseSampleArgs(
        ['--package', 'p', '--out', 'd', '--device', 'EXPLICIT'],
        env: const {'ANDROID_SERIAL': 'ZY22'},
      );
      expect(parsed.serial, 'EXPLICIT');
    });

    test('rejects a missing --package', () {
      expect(
        () => parseSampleArgs(['--out', 'd']),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a missing --out', () {
      expect(
        () => parseSampleArgs(['--package', 'p']),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a bad duration', () {
      expect(
        () => parseSampleArgs([
          '--package',
          'p',
          '--out',
          'd',
          '--interval',
          'soon',
        ]),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unknown flag', () {
      expect(
        () => parseSampleArgs(['--package', 'p', '--out', 'd', '--wat', 'x']),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('runSample usage', () {
    test('missing --package returns exit 2 and writes nothing', () async {
      final err = StringBuffer();
      final code = await runSample(
        ['--out', dir],
        err: err,
        out: StringBuffer(),
      );
      expect(code, 2);
      expect(err.toString(), contains('--package'));
      expect(File('$dir/timeline.json').existsSync(), isFalse);
    });
  });

  group('runSample happy path', () {
    test('samples every interval and writes a valid session', () async {
      final clock = FakeClock();
      final sampler = FakeSampler();
      final adb = ScriptedPidAdb((_) => pidResult(100));

      final code = await run(
        baseArgs(duration: '20s'),
        adb: adb,
        clock: clock,
        sampler: sampler,
      );

      expect(code, 0);
      final timeline = readTimeline(dir);
      // Ticks at t=0,5,10,15 (loop stops once now reaches the 20s deadline).
      expect(
        timeline.columns[TriageColumn.nativePssKb]!.samples.map(
          (s) => s.tMicros,
        ),
        [0, 5000000, 10000000, 15000000],
      );
      expect(readMeta(dir)['endReason'], 'completed');
      expect(readMeta(dir)['package'], 'com.example.app');
    });
  });

  group('gap on failure', () {
    test('a dead-pid tick becomes a coalesced gap, no backoff', () async {
      final clock = FakeClock();
      final sampler = FakeSampler();
      // call0 pid, call1 no-process, call2 pid.
      final adb = ScriptedPidAdb(
        (call) => call == 1 ? noProcessResult() : pidResult(100),
      );

      await run(
        baseArgs(duration: '15s'),
        adb: adb,
        clock: clock,
        sampler: sampler,
      );

      final series = readTimeline(dir).columns[TriageColumn.nativePssKb]!;
      expect(series.samples.map((s) => s.tMicros), [0, 10000000]);
      expect(series.gaps, hasLength(1));
      expect(series.gaps.single.startMicros, 5000000);
      expect(series.gaps.single.endMicros, 5000000);
      // A dead pid is not a device outage: every wait stays at the interval.
      expect(clock.delays, everyElement(const Duration(seconds: 5)));
    });

    test('a per-column sampler miss degrades only that column', () async {
      final clock = FakeClock();
      // native PSS measured; threads unmeasured (an OEM meminfo variance).
      final sampler = FakeSampler(
        reading: (pid) => {
          TriageColumn.nativePssKb: SampleValue.measured(pid),
          TriageColumn.threads: const SampleValue.unmeasured('no Threads row'),
        },
      );
      final adb = ScriptedPidAdb((_) => pidResult(100));

      await run(
        baseArgs(duration: '15s'),
        adb: adb,
        clock: clock,
        sampler: sampler,
      );

      final timeline = readTimeline(dir);
      expect(sampleCount(timeline, TriageColumn.nativePssKb), 3);
      final threads = timeline.columns[TriageColumn.threads]!;
      expect(threads.samples, isEmpty);
      expect(threads.gaps, isNotEmpty);
      expect(threads.gaps.first.reason, contains('no Threads row'));
    });
  });

  group('device outage', () {
    test('backs off, labels one gap over the outage, resumes after', () async {
      final clock = FakeClock();
      final sampler = FakeSampler();
      // call0 ok; calls 1..3 outage; call4+ ok.
      final adb = ScriptedPidAdb(
        (call) =>
            (call >= 1 && call <= 3) ? deviceGoneResult() : pidResult(100),
      );
      final err = StringBuffer();

      await run(
        baseArgs(duration: '50s'),
        adb: adb,
        clock: clock,
        sampler: sampler,
        err: err,
      );

      final series = readTimeline(dir).columns[TriageColumn.nativePssKb]!;
      // Measured before (t=0) and after (t=40) the outage.
      expect(series.samples.map((s) => s.tMicros), containsAll([0, 40000000]));
      // One coalesced gap covering the three outage ticks (t=5,10,20).
      expect(series.gaps, hasLength(1));
      expect(series.gaps.single.startMicros, 5000000);
      expect(series.gaps.single.endMicros, 20000000);
      expect(series.gaps.single.reason, contains('device unreachable'));
      // Backoff grew: 5s → 10s → 20s across the three outage waits.
      expect(
        clock.delays,
        containsAllInOrder(const [
          Duration(seconds: 10),
          Duration(seconds: 20),
        ]),
      );
      expect(err.toString(), contains('device unreachable'));
      expect(err.toString(), contains('retry #'));
    });
  });

  group('wedged device', () {
    test(
      'a hung pidof probe times out to a labeled gap, not a freeze',
      () async {
        final clock = FakeClock();
        final sampler = FakeSampler();
        final hung = Completer<AdbResult>();
        // call1's probe never completes (a wedged `adb shell`); every other
        // probe resolves the pid.
        final adb = _HangingAdb(hungCall: 1, hung: hung.future, pid: 100);
        final err = StringBuffer();

        await runSample(
          baseArgs(duration: '15s'),
          adb: adb,
          clock: clock,
          buildSampler: (_, _) => sampler,
          lock: FakeSessionLock(),
          interrupts: noInterrupts(),
          now: () => DateTime.utc(2026, 7, 17, 3),
          probeTimeout: const Duration(milliseconds: 50),
          out: StringBuffer(),
          err: err,
        );

        final series = readTimeline(dir).columns[TriageColumn.nativePssKb]!;
        expect(
          series.samples.map((s) => s.tMicros),
          containsAll([0, 10000000]),
        );
        expect(series.gaps.single.reason, contains('timed out'));
        expect(err.toString(), contains('device unreachable'));
      },
    );
  });

  group('process restart', () {
    test(
      'marks the pid change, gaps the boundary, resumes on new pid',
      () async {
        final clock = FakeClock();
        final sampler = FakeSampler();
        // call0,1 → pid 100; call2,3 → pid 200 (app restarted).
        final adb = ScriptedPidAdb((call) => pidResult(call < 2 ? 100 : 200));

        await run(
          baseArgs(duration: '20s'),
          adb: adb,
          clock: clock,
          sampler: sampler,
        );

        final timeline = readTimeline(dir);
        final series = timeline.columns[TriageColumn.nativePssKb]!;
        // Old-pid samples at 0,5; new-pid sample at 15; t=10 is the restart gap.
        expect(series.samples.map((s) => s.tMicros), [0, 5000000, 15000000]);
        expect(series.gaps.single.reason, 'process restarted (pid 100→200)');
        final mark = timeline.marks.single;
        expect(mark.label, 'process-restart (pid 100→200)');
        expect(mark.tMicros, 10000000);
        // The restart tick did NOT sample the new pid; the next tick did.
        expect(sampler.sampledPids, [100, 100, 200]);
      },
    );
  });

  group('flush cadence', () {
    test('on-disk timeline is never more than one interval stale', () async {
      final clock = FakeClock();
      final sampler = FakeSampler();
      final adb = ScriptedPidAdb((_) => pidResult(100));
      final onDiskByNow = <int, int>{};
      clock.onAfterDelay = (nowMicros) {
        final file = File('$dir/timeline.json');
        onDiskByNow[nowMicros] = file.existsSync()
            ? sampleCount(readTimeline(dir), TriageColumn.nativePssKb)
            : 0;
      };

      await run(
        baseArgs(duration: '30s', flushEvery: '10s'),
        adb: adb,
        clock: clock,
        sampler: sampler,
      );

      // Flushes land at t=10 and t=20; by t=15 the first three ticks (0,5,10)
      // are durable, by t=25 the first five (0..20) are.
      expect(onDiskByNow[15000000], greaterThanOrEqualTo(3));
      expect(onDiskByNow[25000000], greaterThanOrEqualTo(5));
      // The final flush captures every tick (0,5,10,15,20,25).
      expect(sampleCount(readTimeline(dir), TriageColumn.nativePssKb), 6);
    });
  });

  group('interrupt', () {
    test('SIGINT finalises a valid session and exits 0', () async {
      final clock = FakeClock();
      final sampler = FakeSampler();
      final signals = StreamController<ProcessSignal>(sync: true);
      // Raise SIGINT during the third pidof probe (tick at t=10).
      final adb = ScriptedPidAdb(
        (_) => pidResult(100),
        onCall: (call) {
          if (call == 2) signals.add(ProcessSignal.sigint);
        },
      );
      final err = StringBuffer();

      final code = await run(
        baseArgs(duration: '8h'),
        adb: adb,
        clock: clock,
        sampler: sampler,
        interrupts: signals.stream,
        err: err,
      );

      expect(code, 0);
      // Ticks 0,5,10 completed (the interrupt lands during tick 2's probe but
      // that tick still records) before the loop stops — an 8h session did NOT
      // run to completion.
      expect(sampleCount(readTimeline(dir), TriageColumn.nativePssKb), 3);
      expect(readMeta(dir)['endReason'], 'interrupted');
      expect(err.toString(), contains('interrupted'));
      await signals.close();
    });
  });

  group('finalizeSession (extracted cleanup)', () {
    test('flushes the accumulated timeline and end-stamped meta', () async {
      final store = SessionStore(dir: dir, lock: FakeSessionLock());
      final builder = TimelineBuilder(nowMicros: () => 7000)
        ..add(
          const NativeSampleSnapshot(
            tMicros: 100,
            values: {TriageColumn.nativePssKb: SampleValue.measured(500)},
          ),
        )
        ..addMark('reconnect');
      final meta = SessionMeta(
        package: 'com.example.app',
        device: 'default',
        started: DateTime.utc(2026, 7, 17, 3),
        intervalMicros: 5000000,
        durationMicros: 28800000000,
        flushEveryMicros: 60000000,
      ).ended(DateTime.utc(2026, 7, 17, 4), 'interrupted');

      await finalizeSession(store, builder, meta);

      final timeline = readTimeline(dir);
      expect(sampleCount(timeline, TriageColumn.nativePssKb), 1);
      expect(timeline.marks.single.label, 'reconnect');
      expect(readMeta(dir)['endReason'], 'interrupted');
    });
  });
}
