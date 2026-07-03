import 'adb_runner.dart';
import 'heapprofd_config.dart';

/// Where a heapprofd capture attaches: to an already-running process, or
/// to a freshly launched one (measuring cold-start / early-lifetime
/// memory).
enum CaptureMode { attach, startup }

/// Parameters for a single heapprofd capture session.
class CaptureRequest {
  const CaptureRequest({
    required this.packageId,
    this.mode = CaptureMode.attach,
    this.durationMs = 30000,
    this.samplingIntervalBytes = 4096,
    this.serial,
  });

  /// Android application id of the process to profile.
  final String packageId;

  /// Whether to attach to a running process or launch it fresh.
  final CaptureMode mode;

  /// Total capture duration, in milliseconds.
  final int durationMs;

  /// heapprofd sampling interval, in bytes.
  final int samplingIntervalBytes;

  /// Target device serial; `null` targets the sole connected device.
  final String? serial;
}

/// Captures a heapprofd `.pftrace` from an Android device over `adb`.
abstract interface class NativeHeapCapture {
  /// Runs a heapprofd capture per [request] and pulls the resulting
  /// `.pftrace` to [outputPath], returning [outputPath] on success.
  Future<String> capture(CaptureRequest request, {required String outputPath});
}

Future<void> _realSleep(Duration duration) => Future<void>.delayed(duration);

/// [NativeHeapCapture] backed by `adb shell perfetto` (heapprofd) and
/// `adb pull`, driving both the attach and startup capture modes proven
/// out manually against a device (see the task brief for the exact
/// command sequences).
final class AdbHeapprofdCapture implements NativeHeapCapture {
  AdbHeapprofdCapture(this._runner, {Future<void> Function(Duration)? sleep})
    : _sleep = sleep ?? _realSleep;

  final AdbRunner _runner;
  final Future<void> Function(Duration) _sleep;

  static const _traceDir = '/data/misc/perfetto-traces';

  /// Extra time given to flush the trace to disk after
  /// [CaptureRequest.durationMs] elapses in startup mode, where the host
  /// can't block on the backgrounded `perfetto` process directly.
  static const _startupFlushSlackMs = 3000;

  @override
  Future<String> capture(
    CaptureRequest request, {
    required String outputPath,
  }) async {
    final baseName = _sanitize(request.packageId);
    final cfgPath = '$_traceDir/$baseName.cfg';
    final tracePath = '$_traceDir/$baseName.pftrace';

    await _writeConfig(request, cfgPath);

    await switch (request.mode) {
      CaptureMode.attach => _captureAttach(request, cfgPath, tracePath),
      CaptureMode.startup => _captureStartup(request, cfgPath, tracePath),
    };

    await _run(['pull', tracePath, outputPath], request.serial);
    return outputPath;
  }

  Future<void> _writeConfig(CaptureRequest request, String cfgPath) {
    final config = heapprofdConfig(
      packageId: request.packageId,
      samplingIntervalBytes: request.samplingIntervalBytes,
      durationMs: request.durationMs,
    );
    return _run(['shell', 'cat > $cfgPath'], request.serial, stdin: config);
  }

  /// Blocks on-device for the full capture duration, then returns.
  Future<void> _captureAttach(
    CaptureRequest request,
    String cfgPath,
    String tracePath,
  ) => _run([
    'shell',
    'perfetto',
    '--txt',
    '-c',
    cfgPath,
    '-o',
    tracePath,
  ], request.serial);

  /// Starts a backgrounded trace, force-stops then relaunches the app so
  /// early-lifetime allocations are captured, then waits out the trace.
  Future<void> _captureStartup(
    CaptureRequest request,
    String cfgPath,
    String tracePath,
  ) async {
    await _run([
      'shell',
      'am',
      'force-stop',
      request.packageId,
    ], request.serial);
    await _run([
      'shell',
      'perfetto',
      '--background',
      '--txt',
      '-c',
      cfgPath,
      '-o',
      tracePath,
    ], request.serial);
    await _run([
      'shell',
      'monkey',
      '-p',
      request.packageId,
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ], request.serial);
    await _sleep(
      Duration(milliseconds: request.durationMs + _startupFlushSlackMs),
    );
  }

  Future<AdbResult> _run(
    List<String> args,
    String? serial, {
    String? stdin,
  }) async {
    final result = await _runner.run(args, serial: serial, stdin: stdin);
    if (!result.ok) {
      throw AdbException(args, result.exitCode, result.stderr);
    }
    return result;
  }

  /// Keeps only characters safe for an on-device filename, so an
  /// unexpected package id can't break out of `/data/misc/perfetto-traces`.
  String _sanitize(String packageId) =>
      packageId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
