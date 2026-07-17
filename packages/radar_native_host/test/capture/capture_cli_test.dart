import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

/// Answers `getprop`/`dumpsys` from a scripted substring map; every other
/// call succeeds with empty output.
class _ScriptedAdb implements AdbRunner {
  _ScriptedAdb(this.responses);

  final Map<String, String> responses;

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    final joined = args.join(' ');
    for (final entry in responses.entries) {
      if (joined.contains(entry.key)) return AdbResult(0, entry.value, '');
    }
    return const AdbResult(0, '', '');
  }
}

/// A capture seam that records the request and returns [outputPath] verbatim.
class _FakeCapture implements NativeHeapCapture {
  CaptureRequest? request;
  String? out;

  @override
  Future<String> capture(
    CaptureRequest request, {
    required String outputPath,
  }) async {
    this.request = request;
    out = outputPath;
    return outputPath;
  }
}

/// A validation seam returning canned rows regardless of trace path.
class _FakeValidator implements TraceProcessorRunner {
  _FakeValidator(this.rows);

  final List<PerfettoRow> rows;
  String? queried;

  @override
  Future<List<PerfettoRow>> query(String tracePath) async {
    queried = tracePath;
    return rows;
  }
}

PerfettoRow _row() => const PerfettoRow(
  callsiteId: 1,
  depth: 0,
  function: 'leak',
  module: 'libfoo.so',
  allocBytes: 4096,
  allocCount: 1,
  freeBytes: 0,
  freeCount: 0,
);

void main() {
  group('runCapture', () {
    final passingAdb = _ScriptedAdb({
      'ro.build.version.sdk': '34\n',
      'dumpsys package': 'flags=[ DEBUGGABLE HAS_CODE ]\n',
    });

    test('happy path: preflight passes, captures, validates, exit 0', () async {
      final capture = _FakeCapture();
      final validator = _FakeValidator([_row()]);
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runCapture(
        ['--package', 'com.x', '--out', '/tmp/cap.pftrace'],
        adb: passingAdb,
        capture: capture,
        validator: validator,
        out: out,
        err: err,
      );

      expect(code, 0);
      expect(capture.request!.packageId, 'com.x');
      expect(capture.out, '/tmp/cap.pftrace');
      expect(validator.queried, '/tmp/cap.pftrace');
      expect(out.toString(), contains('/tmp/cap.pftrace'));
      expect(err.toString(), isEmpty);
    });

    test('old SDK: exit 2 (tool failure) naming the deviceApiLevel check, no '
        'capture', () async {
      final oldAdb = _ScriptedAdb({
        'ro.build.version.sdk': '28\n',
        'dumpsys package': 'flags=[ DEBUGGABLE ]\n',
      });
      final capture = _FakeCapture();
      final err = StringBuffer();

      final code = await runCapture(
        ['--package', 'com.x', '--out', '/tmp/cap.pftrace'],
        adb: oldAdb,
        capture: capture,
        validator: _FakeValidator([_row()]),
        err: err,
      );

      expect(code, 2);
      expect(err.toString(), contains('deviceApiLevel'));
      expect(err.toString(), contains('29'));
      expect(capture.request, isNull);
    });

    test('not profileable: exit 2 (tool failure) naming the packageProfileable '
        'check', () async {
      final userAdb = _ScriptedAdb({
        'ro.build.version.sdk': '33\n',
        'ro.build.type': 'user\n',
        'dumpsys package': 'flags=[ HAS_CODE ]\n',
      });
      final capture = _FakeCapture();
      final err = StringBuffer();

      final code = await runCapture(
        ['--package', 'com.x', '--out', '/tmp/cap.pftrace'],
        adb: userAdb,
        capture: capture,
        validator: _FakeValidator([_row()]),
        err: err,
      );

      expect(code, 2);
      expect(err.toString(), contains('packageProfileable'));
      expect(capture.request, isNull);
    });

    test('empty capture: post-capture validation fails, exit 2 (tool failure) '
        'naming capturedHeapData', () async {
      final capture = _FakeCapture();
      final err = StringBuffer();

      final code = await runCapture(
        ['--package', 'com.x', '--out', '/tmp/cap.pftrace'],
        adb: passingAdb,
        capture: capture,
        validator: _FakeValidator(const []),
        err: err,
      );

      expect(code, 2);
      expect(err.toString(), contains('capturedHeapData'));
      // The capture DID run — validation is what failed.
      expect(capture.request, isNotNull);
    });

    test('startup mode flag is threaded into the capture request', () async {
      final capture = _FakeCapture();

      await runCapture(
        [
          '--package',
          'com.x',
          '--out',
          '/tmp/cap.pftrace',
          '--mode',
          'startup',
          '--duration',
          '20s',
        ],
        adb: passingAdb,
        capture: capture,
        validator: _FakeValidator([_row()]),
        out: StringBuffer(),
        err: StringBuffer(),
      );

      expect(capture.request!.mode, CaptureMode.startup);
      expect(capture.request!.durationMs, 20000);
    });

    test('missing --package: exit 1 usage error', () async {
      final err = StringBuffer();
      final code = await runCapture(
        ['--out', '/tmp/cap.pftrace'],
        adb: passingAdb,
        capture: _FakeCapture(),
        validator: _FakeValidator([_row()]),
        err: err,
      );

      expect(code, 1);
      expect(err.toString(), contains('--package'));
    });

    test('missing --out: exit 1 usage error', () async {
      final err = StringBuffer();
      final code = await runCapture(
        ['--package', 'com.x'],
        adb: passingAdb,
        capture: _FakeCapture(),
        validator: _FakeValidator([_row()]),
        err: err,
      );

      expect(code, 1);
      expect(err.toString(), contains('--out'));
    });
  });
}
