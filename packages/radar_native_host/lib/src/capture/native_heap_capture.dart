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
    : _sleep = sleep ?? _realSleep,
      _pollInterval = const Duration(seconds: 2);

  AdbHeapprofdCapture.withPollInterval(
    this._runner, {
    required Future<void> Function(Duration) sleep,
    required Duration pollInterval,
  }) : _sleep = sleep,
       _pollInterval = pollInterval;

  final AdbRunner _runner;
  final Future<void> Function(Duration) _sleep;
  final Duration _pollInterval;

  static const _traceDir = '/data/misc/perfetto-traces';

  /// Extra time, beyond [CaptureRequest.durationMs], allowed for the
  /// backgrounded `perfetto` process to self-terminate and flush its trace to
  /// disk before startup-mode polling gives up. The config's `duration_ms`
  /// bounds the capture; this only bounds how long we *wait* for a
  /// backgrounded process the host cannot block on directly.
  static const _startupFlushSlackMs = 15000;

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
  /// early-lifetime allocations are captured, then waits for the trace to
  /// finish.
  ///
  /// `perfetto --background` prints the tracing session's pid to stdout, so we
  /// poll `/proc/<pid>` and return the moment that process exits — real
  /// completion, not a blind duration. If the pid can't be parsed (an older
  /// `perfetto`, or unexpected output) we fall back to the original fixed wait
  /// of `duration_ms + slack`: the one remaining time-based path, taken only
  /// when the completion signal is unavailable.
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
    final background = await _run([
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

    final perfettoPid = _firstInt(background.stdout);
    final maxWait = Duration(
      milliseconds: request.durationMs + _startupFlushSlackMs,
    );
    if (perfettoPid == null) {
      await _sleep(maxWait);
      return;
    }
    await _awaitProcessExit(perfettoPid, request.serial, maxWait);
  }

  /// Polls `/proc/<pid>` until the perfetto process exits or [maxWait] elapses,
  /// whichever comes first. Elapsed time is accumulated from [_pollInterval]
  /// (not a wall clock) so an injected fake sleep drives the loop
  /// deterministically. The `test -d` probe is read-only — a non-zero exit is
  /// the expected "process gone" signal, so it bypasses [_run]'s throw.
  Future<void> _awaitProcessExit(
    int pid,
    String? serial,
    Duration maxWait,
  ) async {
    var elapsed = Duration.zero;
    while (elapsed < maxWait) {
      final alive = await _runner.run([
        'shell',
        'test',
        '-d',
        '/proc/$pid',
      ], serial: serial);
      if (!alive.ok) return;
      await _sleep(_pollInterval);
      elapsed += _pollInterval;
    }
  }

  /// The first non-negative integer token in [text] (perfetto prints its
  /// backgrounded pid on its own line), or null when none is present.
  int? _firstInt(String text) {
    for (final token in text.trim().split(RegExp(r'\s+'))) {
      final value = int.tryParse(token);
      if (value != null && value >= 0) return value;
    }
    return null;
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
