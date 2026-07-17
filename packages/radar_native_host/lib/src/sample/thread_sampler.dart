import 'package:radar_native/radar_native.dart';

import '../capture/adb_runner.dart';
import 'sample_snapshot.dart';

final _digitRun = RegExp(r'\d+');

/// A parsed `task/*/comm` reading: the total thread count plus a per-name
/// breakdown for spotting runaway thread pools.
///
/// Names are grouped by *prefix* — each comm with its digit runs collapsed to
/// `#` — so `pool-1-thread-1`, `pool-1-thread-2`, … coalesce into one
/// `pool-#-thread-#` bucket. A pool that leaks threads then reads as a single,
/// fast-growing prefix rather than dozens of singletons.
final class ThreadCommBreakdown {
  /// Wraps the ordered thread [names] (one per live task).
  const ThreadCommBreakdown(this.names);

  /// The thread (comm) names, in the order read.
  final List<String> names;

  /// Total live thread count.
  int get total => names.length;

  /// The [n] most common name prefixes (digit runs collapsed to `#`),
  /// descending by count. Ties keep first-appearance order, so the result is
  /// deterministic. Returns an empty map for `n <= 0`.
  Map<String, int> topThreadNamePrefixes(int n) {
    if (n <= 0) return const {};
    final counts = <String, int>{};
    final firstIndex = <String, int>{};
    for (var i = 0; i < names.length; i++) {
      final prefix = names[i].replaceAll(_digitRun, '#');
      counts[prefix] = (counts[prefix] ?? 0) + 1;
      firstIndex.putIfAbsent(prefix, () => i);
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return firstIndex[a.key]!.compareTo(firstIndex[b.key]!);
      });
    return {for (final entry in entries.take(n)) entry.key: entry.value};
  }
}

/// Samples `cat /proc/<pid>/task/*/comm` — the live thread count, and a
/// name-prefix breakdown via [breakdown].
///
/// Known-good shape (parsed): one comm name per line, the device shell having
/// expanded the `task/*/comm` glob. A dead pid leaves the glob unexpanded, so
/// the device shell emits a `No such file` error for the literal path — that
/// (or a non-zero exit, or empty output) reads not-measured, never a zero
/// thread count.
///
/// Boundary: a partial read (some `task/*/comm` files erroring mid-race as
/// threads exit) refuses the whole reading rather than reporting a wrong-low
/// count — an unmeasured miss is preferred over a plausible-but-wrong number.
/// `/proc/<pid>/status` `Threads:` (see [ProcStatusSampler]) is the race-free
/// count; this sampler's value-add is the [breakdown].
final class ThreadSampler implements NativeSampler {
  /// Samples via [_adb], optionally scoped to device [serial].
  const ThreadSampler(this._adb, {this.serial});

  final AdbRunner _adb;

  /// Target device serial; `null` targets the sole connected device.
  final String? serial;

  static const _columns = {TriageColumn.threads};

  @override
  Set<TriageColumn> get columns => _columns;

  @override
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid) async {
    final breakdown = await this.breakdown(package, pid);
    if (breakdown == null) {
      return allUnmeasured(
        _columns,
        'could not read /proc/$pid/task/*/comm (dead pid or unreadable)',
      );
    }
    return {TriageColumn.threads: SampleValue.measured(breakdown.total)};
  }

  /// Reads the raw thread-name breakdown, or `null` when unmeasured. Exposes
  /// the per-prefix detail [sample] reduces to a single count.
  Future<ThreadCommBreakdown?> breakdown(String package, int pid) async {
    final result = await _adb.run([
      'shell',
      'cat',
      '/proc/$pid/task/*/comm',
    ], serial: serial);
    if (!result.ok) return null;
    return parseThreadComm(result.stdout);
  }
}

/// Parses `cat /proc/<pid>/task/*/comm` [output] into a [ThreadCommBreakdown],
/// or `null` when the output is a shell error or carries no thread name — the
/// signal to read the thread column not-measured rather than zero.
ThreadCommBreakdown? parseThreadComm(String output) {
  if (output.contains('No such file') || output.contains('Permission denied')) {
    return null;
  }
  final names = [
    for (final line in output.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (names.isEmpty) return null;
  return ThreadCommBreakdown(names);
}
