import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

class _RecordedCall {
  const _RecordedCall(this.args, this.serial, this.stdin);

  final List<String> args;
  final String? serial;
  final String? stdin;
}

class _RecordingAdbRunner implements AdbRunner {
  final calls = <_RecordedCall>[];

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    calls.add(_RecordedCall(args, serial, stdin));
    return const AdbResult(0, '', '');
  }
}

/// Fails only the call whose second arg (the on-device binary) matches
/// [failingBinary]; every other call succeeds.
class _FailingAdbRunner implements AdbRunner {
  _FailingAdbRunner(this.failingBinary);

  final String failingBinary;

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    if (args.length > 1 && args[1] == failingBinary) {
      return const AdbResult(1, '', 'boom');
    }
    return const AdbResult(0, '', '');
  }
}

/// Drives startup-mode completion polling: `perfetto --background` reports
/// [backgroundStdout], and `test -d /proc/<pid>` reads alive (exit 0) for the
/// first [aliveProbes] probes, then gone (exit 1).
class _PollingAdbRunner implements AdbRunner {
  _PollingAdbRunner({
    required this.backgroundStdout,
    required this.aliveProbes,
  });

  final String backgroundStdout;
  final int aliveProbes;
  final calls = <List<String>>[];
  int _probes = 0;

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    calls.add(args);
    if (args.contains('--background')) {
      return AdbResult(0, backgroundStdout, '');
    }
    if (args.length > 1 && args[1] == 'test' && args.contains('-d')) {
      final alive = _probes < aliveProbes;
      _probes++;
      return AdbResult(alive ? 0 : 1, '', '');
    }
    return const AdbResult(0, '', '');
  }

  int get procProbeCount =>
      calls.where((c) => c.length > 1 && c[1] == 'test').length;
}

class _RecordingSleep {
  Duration? lastDuration;

  Future<void> call(Duration duration) async {
    lastDuration = duration;
  }
}

void main() {
  group('AdbHeapprofdCapture', () {
    test('attach mode: config write, blocking perfetto, then pull', () async {
      final runner = _RecordingAdbRunner();
      final sleep = _RecordingSleep();
      final capture = AdbHeapprofdCapture(runner, sleep: sleep.call);

      final result = await capture.capture(
        const CaptureRequest(packageId: 'com.x', durationMs: 20000),
        outputPath: '/tmp/o.pftrace',
      );

      expect(result, '/tmp/o.pftrace');
      expect(runner.calls, hasLength(3));

      final configWrite = runner.calls[0];
      expect(configWrite.args, hasLength(2));
      expect(configWrite.args[0], 'shell');
      expect(configWrite.args[1], startsWith('cat > '));
      expect(configWrite.serial, isNull);
      expect(configWrite.stdin, contains('process_cmdline: "com.x"'));
      expect(configWrite.stdin, contains('duration_ms: 20000'));

      final perfetto = runner.calls[1];
      expect(perfetto.args[0], 'shell');
      expect(perfetto.args[1], 'perfetto');
      expect(perfetto.args, containsAllInOrder(['-c']));
      expect(perfetto.args, containsAllInOrder(['-o']));
      expect(perfetto.args, isNot(contains('--background')));

      final pull = runner.calls[2];
      expect(pull.args[0], 'pull');
      expect(pull.args[2], '/tmp/o.pftrace');

      expect(sleep.lastDuration, isNull);
    });

    test('startup mode: force-stop, backgrounded perfetto, monkey launch, '
        'then polls /proc for completion before pulling', () async {
      final runner = _PollingAdbRunner(
        backgroundStdout: '4321\n',
        aliveProbes: 2,
      );
      final sleep = _RecordingSleep();
      final capture = AdbHeapprofdCapture.withPollInterval(
        runner,
        sleep: sleep.call,
        pollInterval: const Duration(seconds: 2),
      );

      final result = await capture.capture(
        const CaptureRequest(
          packageId: 'com.x',
          mode: CaptureMode.startup,
          durationMs: 12000,
          serial: 'DEV123',
        ),
        outputPath: '/tmp/o.pftrace',
      );

      expect(result, '/tmp/o.pftrace');

      // Ordered prefix: config write, force-stop, backgrounded perfetto, monkey.
      expect(runner.calls[0].first, 'shell');
      expect(runner.calls[0][1], startsWith('cat > '));
      expect(runner.calls[1], ['shell', 'am', 'force-stop', 'com.x']);
      expect(runner.calls[2], contains('--background'));
      expect(runner.calls[3], contains('monkey'));

      // Polling: the /proc probe targets the reported pid and runs until the
      // process is gone (2 alive + 1 gone = 3 probes) — not a blind sleep.
      expect(runner.procProbeCount, 3);
      expect(
        runner.calls,
        contains(equals(['shell', 'test', '-d', '/proc/4321'])),
      );

      // The last call is the pull; it only happened after polling saw the
      // process exit.
      expect(runner.calls.last.first, 'pull');

      // The only sleeps are poll-cadence waits between probes, never one blind
      // duration-length wait.
      expect(sleep.lastDuration, const Duration(seconds: 2));
    });

    test('startup mode: falls back to a fixed wait when the perfetto pid '
        'cannot be parsed', () async {
      final runner = _PollingAdbRunner(
        backgroundStdout: 'Connected to the Perfetto traced service\n',
        aliveProbes: 0,
      );
      final sleep = _RecordingSleep();
      final capture = AdbHeapprofdCapture.withPollInterval(
        runner,
        sleep: sleep.call,
        pollInterval: const Duration(seconds: 2),
      );

      await capture.capture(
        const CaptureRequest(
          packageId: 'com.x',
          mode: CaptureMode.startup,
          durationMs: 12000,
        ),
        outputPath: '/tmp/o.pftrace',
      );

      // No pid → no /proc polling; the documented time-based fallback wait of
      // duration + slack (12000 + 15000) is used instead.
      expect(runner.procProbeCount, 0);
      expect(sleep.lastDuration, const Duration(milliseconds: 27000));
      expect(runner.calls.last.first, 'pull');
    });

    test('throws AdbException when the perfetto step fails', () async {
      final runner = _FailingAdbRunner('perfetto');
      final capture = AdbHeapprofdCapture(runner, sleep: (_) async {});

      await expectLater(
        capture.capture(
          const CaptureRequest(packageId: 'com.x'),
          outputPath: '/tmp/o.pftrace',
        ),
        throwsA(isA<AdbException>()),
      );
    });

    test(
      'sanitizes an unsafe packageId out of the on-device cfg/trace paths',
      () async {
        final runner = _RecordingAdbRunner();
        final capture = AdbHeapprofdCapture(runner, sleep: (_) async {});

        await capture.capture(
          const CaptureRequest(packageId: 'com.x/../y'),
          outputPath: '/tmp/o.pftrace',
        );

        final configWrite = runner.calls[0];
        expect(configWrite.args[1], contains('com.x_.._y.cfg'));
        expect(configWrite.args[1], isNot(contains('/../')));

        final perfetto = runner.calls[1];
        expect(
          perfetto.args,
          contains('/data/misc/perfetto-traces/com.x_.._y.cfg'),
        );
        expect(perfetto.args, isNot(anyElement(contains('/../'))));

        final pull = runner.calls[2];
        expect(pull.args[1], '/data/misc/perfetto-traces/com.x_.._y.pftrace');
      },
    );
  });
}
