import 'adb_runner.dart';

/// The named preconditions a heapprofd capture depends on. Every failure a
/// caller surfaces cites exactly one of these, so an operator sees *which*
/// gate blocked the capture rather than a bare non-zero exit.
enum PreflightCheck {
  /// The device API level is high enough for heapprofd (SDK >= 29).
  deviceApiLevel,

  /// The target package is profileable-by-shell or debuggable (or the whole
  /// device build is debuggable), so heapprofd is permitted to attach.
  packageProfileable,

  /// The pulled trace actually contains heap_profile allocation data — the
  /// post-capture validation, checked by the capture verb (not [CapturePreflight]).
  capturedHeapData,
}

/// The minimum Android API level heapprofd is available on.
const int kMinHeapprofdSdk = 29;

/// A single failed [PreflightCheck] plus the actionable reason.
final class PreflightFailure {
  /// Creates a failure for [check] with an operator-facing [message].
  const PreflightFailure(this.check, this.message);

  /// Which named gate failed.
  final PreflightCheck check;

  /// A specific, actionable explanation naming the gate and the observed value.
  final String message;
}

/// The outcome of running the pre-capture gates.
final class PreflightResult {
  const PreflightResult._(this.failure);

  /// A passing result carries no failure.
  const PreflightResult.pass() : this._(null);

  /// A failing result carries the single blocking [PreflightFailure].
  const PreflightResult.fail(PreflightFailure failure) : this._(failure);

  /// The blocking failure, or null when every gate passed.
  final PreflightFailure? failure;

  /// Whether every gate passed.
  bool get passed => failure == null;
}

/// Runs the two device-side preconditions a heapprofd capture needs *before*
/// spending 30s on a capture that could never have produced data: the device
/// API level (`getprop ro.build.version.sdk`) and whether the target package
/// may be profiled (`dumpsys package` flags, with a debuggable-device-build
/// fast path).
///
/// Read-only shell probes only — no state is changed on the device. The
/// post-capture [PreflightCheck.capturedHeapData] validation is not run here
/// (it needs the pulled trace); the capture verb runs it after the pull.
final class CapturePreflight {
  /// Creates a preflight runner over [_runner].
  const CapturePreflight(this._runner);

  final AdbRunner _runner;

  /// Runs the pre-capture gates for [packageId] on [serial], short-circuiting
  /// at the first failure so the reported check is the earliest blocker.
  Future<PreflightResult> check(
    String packageId, {
    required String? serial,
  }) async {
    final sdkResult = await _checkSdk(serial);
    if (!sdkResult.passed) return sdkResult;
    return _checkProfileable(packageId, serial);
  }

  Future<PreflightResult> _checkSdk(String? serial) async {
    final raw = await _getprop('ro.build.version.sdk', serial);
    final sdk = int.tryParse(raw.trim());
    if (sdk == null) {
      return PreflightResult.fail(
        PreflightFailure(
          PreflightCheck.deviceApiLevel,
          'could not read device API level via '
          '`getprop ro.build.version.sdk` (got "${raw.trim()}") — heapprofd '
          'needs SDK >= $kMinHeapprofdSdk',
        ),
      );
    }
    if (sdk < kMinHeapprofdSdk) {
      return PreflightResult.fail(
        PreflightFailure(
          PreflightCheck.deviceApiLevel,
          'device API level $sdk is below $kMinHeapprofdSdk — heapprofd is '
          'unavailable on this device',
        ),
      );
    }
    return const PreflightResult.pass();
  }

  Future<PreflightResult> _checkProfileable(
    String packageId,
    String? serial,
  ) async {
    // A debuggable/userdebug/eng device build makes every process profileable,
    // so the per-package flag is moot there — check the cheaper device gate
    // first.
    if (await _deviceIsDebuggable(serial)) return const PreflightResult.pass();

    final dump = await _dumpsysPackage(packageId, serial);
    if (_packageAllowsProfiling(dump)) return const PreflightResult.pass();

    return PreflightResult.fail(
      PreflightFailure(
        PreflightCheck.packageProfileable,
        'package "$packageId" is neither debuggable nor '
        'profileable-by-shell on this user build — heapprofd cannot attach. '
        'Add `<profileable android:shell="true"/>` to the manifest, use a '
        'debuggable build, or run on a userdebug device',
      ),
    );
  }

  Future<bool> _deviceIsDebuggable(String? serial) async {
    if ((await _getprop('ro.debuggable', serial)).trim() == '1') return true;
    final buildType = (await _getprop('ro.build.type', serial)).trim();
    return buildType == 'userdebug' || buildType == 'eng';
  }

  /// True when [dumpsys] output marks the package DEBUGGABLE or PROFILEABLE
  /// (covering `PROFILEABLE_BY_SHELL`). Matched case-insensitively so a
  /// vendor's flag casing cannot hide a genuine grant.
  static bool _packageAllowsProfiling(String dumpsys) {
    final upper = dumpsys.toUpperCase();
    return upper.contains('DEBUGGABLE') || upper.contains('PROFILEABLE');
  }

  Future<String> _getprop(String property, String? serial) async {
    final result = await _runner.run([
      'shell',
      'getprop',
      property,
    ], serial: serial);
    return result.ok ? result.stdout : '';
  }

  Future<String> _dumpsysPackage(String packageId, String? serial) async {
    final result = await _runner.run([
      'shell',
      'dumpsys',
      'package',
      packageId,
    ], serial: serial);
    return result.ok ? result.stdout : '';
  }
}
