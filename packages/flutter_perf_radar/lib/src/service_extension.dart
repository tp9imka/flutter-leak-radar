import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'build_mode.dart';
import 'facade/perf_radar.dart';

/// Whether the VM service extension has already been registered.
///
/// Guards against double-registration when [registerPerfRadarExtension]
/// is called more than once (e.g. after a hot-restart in tests).
bool _registered = false;

/// Assembles a complete JSON-encodable snapshot of all PerfRadar subsystems.
///
/// Returns a plain [Map] whose keys are:
///
/// - `"traces"` — [TraceSnapshot] for every recorded span key:
///   ```json
///   {
///     "totalDropCount": 0,
///     "keys": [
///       {
///         "name": "db.query.rooms",
///         "category": "db",
///         "count": 42,
///         "meanMicros": 1200,
///         "maxMicros": 8000,
///         "totalMicros": 50400,
///         "p50": 1100,
///         "p95": 4000,
///         "p99": 7000,
///         "avgInterCallIntervalMicros": 500,
///         "callsPerSecond": 2.0,
///         "errorCount": 1,
///         "firstStartMicros": 1000000,
///         "lastStartMicros": 22000000
///       }
///     ]
///   }
///   ```
///
/// - `"frames"` — Frame timing statistics:
///   ```json
///   {
///     "frameCount": 300,
///     "jankCount": 4,
///     "buildP50": 800,   "buildP95": 3000,  "buildP99": 6000,
///     "rasterP50": 900,  "rasterP95": 3200, "rasterP99": 6500,
///     "totalP50": 1800,  "totalP95": 6000,  "totalP99": 12000,
///     "recentFrames": [
///       { "totalMicros": 16200, "buildMicros": 800, "rasterMicros": 900 }
///     ]
///   }
///   ```
///   Percentile fields are `null` when no frames have been recorded.
///
/// - `"stability"` — Error and stall counters with retained recent events:
///   ```json
///   {
///     "errorCount": 2,
///     "stallCount": 1,
///     "recentErrors": [
///       {
///         "message": "Connection refused",
///         "context": "FlutterError",
///         "clockMicros": 123456789,
///         "stackTraceString": "..."
///       }
///     ],
///     "recentStalls": [
///       { "durationMicros": 320000, "clockMicros": 987654321 }
///     ]
///   }
///   ```
///   `context` and `stackTraceString` are `null` when absent from the
///   underlying [ErrorRecord].
///
/// This function is pure — it only reads current [PerfRadar] snapshots and
/// delegates to the individual `toJson()` methods. It never registers the
/// VM service extension itself; call [registerPerfRadarExtension] for that.
Map<String, Object?> perfRadarSnapshotJson() => {
  'traces': PerfRadar.snapshot().toJson(),
  'frames': PerfRadar.frameStats.toJson(),
  'stability': PerfRadar.stabilitySnapshot.toJson(),
};

/// Registers the `ext.perf_radar.snapshot` VM service extension.
///
/// Must be called from [PerfRadar.init] after the engine is running.
/// Guarded by [kPerfEnabled] — never registers in release builds.
/// Safe to call multiple times; subsequent calls after the first are
/// no-ops (the [_registered] flag prevents double-registration).
///
/// The extension responds to `ext.perf_radar.snapshot` with the JSON
/// produced by [perfRadarSnapshotJson]. On error it returns a structured
/// [ServiceExtensionResponse.error] and logs via [developer.log] — it
/// never throws into the host app.
void registerPerfRadarExtension() {
  if (!kPerfEnabled) return;
  if (_registered) return;
  _registered = true;

  developer.registerExtension('ext.perf_radar.snapshot', (
    method,
    params,
  ) async {
    try {
      final json = jsonEncode(perfRadarSnapshotJson());
      return developer.ServiceExtensionResponse.result(json);
    } catch (e, st) {
      developer.log(
        'ext.perf_radar.snapshot error: $e',
        name: 'flutter_perf_radar',
        error: e,
        stackTrace: st,
      );
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'perf_radar snapshot failed: $e',
      );
    }
  });
}

/// Resets the registration guard.
///
/// Visible for testing only — allows tests to re-register the extension
/// after calling [registerPerfRadarExtension] in a previous test case.
@visibleForTesting
void resetExtensionRegistrationForTesting() => _registered = false;
