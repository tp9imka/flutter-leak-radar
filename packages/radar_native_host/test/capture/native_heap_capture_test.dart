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
        'sleep, then pull', () async {
      final runner = _RecordingAdbRunner();
      final sleep = _RecordingSleep();
      final capture = AdbHeapprofdCapture(runner, sleep: sleep.call);

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
      expect(runner.calls, hasLength(5));
      for (final call in runner.calls) {
        expect(call.serial, 'DEV123');
      }

      expect(runner.calls[0].args[0], 'shell');
      expect(runner.calls[0].args[1], startsWith('cat > '));

      expect(runner.calls[1].args, ['shell', 'am', 'force-stop', 'com.x']);

      final perfetto = runner.calls[2];
      expect(perfetto.args[0], 'shell');
      expect(perfetto.args, contains('perfetto'));
      expect(perfetto.args, contains('--background'));

      expect(runner.calls[3].args, [
        'shell',
        'monkey',
        '-p',
        'com.x',
        '-c',
        'android.intent.category.LAUNCHER',
        '1',
      ]);

      expect(sleep.lastDuration, const Duration(milliseconds: 15000));

      expect(runner.calls[4].args[0], 'pull');
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
