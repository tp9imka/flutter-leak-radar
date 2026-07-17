import 'package:radar_native/radar_native.dart';

import '../capture/adb_runner.dart';
import 'sample_snapshot.dart';

/// `/proc/<pid>/status` keys, each requiring the trailing `kB` unit token so an
/// unexpected unit refuses rather than mis-scales.
final _vmRss = RegExp(r'^VmRSS:\s+(\d+)\s+kB', multiLine: true);
final _rssAnon = RegExp(r'^RssAnon:\s+(\d+)\s+kB', multiLine: true);
final _threads = RegExp(r'^Threads:\s+(\d+)', multiLine: true);

/// Samples `/proc/<pid>/status` — VmRSS, RssAnon (both KiB), and the kernel's
/// Threads count.
///
/// Known-good shape (parsed): the standard `key:\t<value> kB` /
/// `Threads:\t<n>` lines Linux exposes on every Android release. VmRSS/RssAnon
/// are trusted only when the `kB` unit is present — a hypothetical OEM kernel
/// reporting a different unit reads not-measured rather than being mis-scaled.
/// A dead pid (`No such file`, non-zero exit) reads not-measured for all three.
///
/// Per-key boundary: `RssAnon` only appears on kernel 4.5+ (most Android 8+
/// devices). On an older kernel that omits it, `rssAnonKb` reads not-measured
/// while `vmRssKb`/`threads` still measure — an honest per-column miss, never a
/// zero.
final class ProcStatusSampler implements NativeSampler {
  /// Samples via [_adb], optionally scoped to device [serial].
  const ProcStatusSampler(this._adb, {this.serial});

  final AdbRunner _adb;

  /// Target device serial; `null` targets the sole connected device.
  final String? serial;

  static const _columns = {
    TriageColumn.rssAnonKb,
    TriageColumn.vmRssKb,
    TriageColumn.threads,
  };

  @override
  Set<TriageColumn> get columns => _columns;

  @override
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid) async {
    final result = await _adb.run([
      'shell',
      'cat',
      '/proc/$pid/status',
    ], serial: serial);
    if (!result.ok) {
      return allUnmeasured(
        _columns,
        'cat /proc/$pid/status exited ${result.exitCode}: '
        '${result.stderr.trim()}',
      );
    }
    return parseProcStatus(result.stdout);
  }
}

/// Parses raw `/proc/<pid>/status` [output] into the RssAnon, VmRSS, and
/// Threads columns. A key absent (or a memory key without its `kB` unit) reads
/// not-measured for that column — never a fabricated zero.
Map<TriageColumn, SampleValue> parseProcStatus(String output) {
  final found = <TriageColumn, int>{};
  // tryParse throughout: an implausibly long digit run leaves the column
  // not-measured rather than throwing a swept-away FormatException.
  if (_vmRss.firstMatch(output)?.group(1) case final digits?) {
    if (int.tryParse(digits) case final value?) {
      found[TriageColumn.vmRssKb] = value;
    }
  }
  if (_rssAnon.firstMatch(output)?.group(1) case final digits?) {
    if (int.tryParse(digits) case final value?) {
      found[TriageColumn.rssAnonKb] = value;
    }
  }
  if (_threads.firstMatch(output)?.group(1) case final digits?) {
    if (int.tryParse(digits) case final value?) {
      found[TriageColumn.threads] = value;
    }
  }
  return readingsFrom(
    ProcStatusSampler._columns,
    found,
    (column) => '/proc/<pid>/status ${column.name} not found',
  );
}
