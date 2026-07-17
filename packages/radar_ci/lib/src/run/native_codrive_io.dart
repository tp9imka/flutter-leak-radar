import 'dart:async';

import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';

import 'native_codrive.dart';

/// Default bound on one native co-drive sweep, so a hung `dumpsys` degrades to
/// an unmeasured tick instead of stalling the whole run.
const Duration _defaultSampleTimeout = Duration(seconds: 15);

/// Default bound on the per-tick `adb pidof` probe.
const Duration _defaultProbeTimeout = Duration(seconds: 8);

/// A [NativeCoSampler] backed by `adb`: re-resolves the target pid each tick
/// and reads the Lane A columns through the shared [defaultNativeSampler]
/// composite.
///
/// Honest by construction — never throws, never fabricates a zero:
/// - the app not running (or the device unreachable) → every column unmeasured
///   for that tick (a gap), and the run keeps sampling;
/// - a sweep hung past [sampleTimeout] → the same all-unmeasured tick;
/// - a single sampler throwing is already isolated per column by
///   [CompositeSampler], so one bad column never loses the tick.
///
/// Pid is re-resolved every tick so an app restart mid-run simply reads gone
/// for a tick and then resumes on the new pid — the co-drive stays simple and
/// leaves overnight-grade outage handling to the `radar_sample` loop.
final class AdbNativeCoSampler implements NativeCoSampler {
  /// Creates a co-sampler for [package] over [sampler], scoped to [serial].
  AdbNativeCoSampler({
    required this.adb,
    required this.package,
    required this.sampler,
    this.serial,
    this.probeTimeout = _defaultProbeTimeout,
    this.sampleTimeout = _defaultSampleTimeout,
  });

  /// Builds a co-sampler over the default Lane A composite for [package].
  factory AdbNativeCoSampler.defaults({
    required AdbRunner adb,
    required String package,
    String? serial,
  }) => AdbNativeCoSampler(
    adb: adb,
    package: package,
    serial: serial,
    sampler: defaultNativeSampler(adb, serial),
  );

  /// The adb seam.
  final AdbRunner adb;

  /// Target Android package.
  final String package;

  /// The Lane A sampler read each tick.
  final NativeSampler sampler;

  /// Device serial, or null for the sole connected device.
  final String? serial;

  /// Bound on the per-tick `pidof` probe.
  final Duration probeTimeout;

  /// Bound on one sampling sweep.
  final Duration sampleTimeout;

  @override
  Future<Map<TriageColumn, SampleValue>> sampleAt(int tMicros) async {
    final pid = await _resolvePid();
    if (pid == null) {
      return allUnmeasured(
        sampler.columns,
        'process not running / device unreachable',
      );
    }
    try {
      return await sampler.sample(package, pid).timeout(sampleTimeout);
    } on TimeoutException {
      return allUnmeasured(
        sampler.columns,
        'native sweep timed out after ${sampleTimeout.inSeconds}s',
      );
    } catch (error) {
      return allUnmeasured(sampler.columns, 'native sweep failed: $error');
    }
  }

  Future<int?> _resolvePid() async {
    try {
      final result = await adb
          .run(['shell', 'pidof', '-s', package], serial: serial)
          .timeout(probeTimeout);
      for (final token in result.stdout.trim().split(RegExp(r'\s+'))) {
        final value = int.tryParse(token);
        if (value != null && value > 0) return value;
      }
    } catch (_) {
      // Any probe failure (timeout, adb absent, device gone) reads as gone.
    }
    return null;
  }
}
