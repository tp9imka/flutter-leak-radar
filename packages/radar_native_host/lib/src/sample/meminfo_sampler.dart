import 'package:radar_native/radar_native.dart';

import '../capture/adb_runner.dart';
import 'sample_snapshot.dart';

/// The `dumpsys meminfo` App Summary labels this sampler trends, mapped to
/// their [TriageColumn]. The App Summary reports Pss already in KiB (its header
/// reads `Pss(KB)`), so no unit conversion is applied — the values pass through
/// as `'kb'`.
const _labelColumns = <String, TriageColumn>{
  'Java Heap': TriageColumn.javaHeapKb,
  'Native Heap': TriageColumn.nativePssKb,
  'Code': TriageColumn.codeKb,
  'Graphics': TriageColumn.graphicsKb,
};

final _summaryRow = RegExp(r'^\s*([A-Za-z][A-Za-z /]*?):\s+(\d+)');
final _totalRow = RegExp(r'^\s*TOTAL(?: PSS)?:\s+(\d+)');

/// Samples the `dumpsys meminfo <package>` App Summary — Java Heap, Native
/// Heap, Code, Graphics, TOTAL PSS.
///
/// Known-good shapes (parsed): the modern two-column App Summary
/// (`Pss(KB)` / `Rss(KB)`) of Android 11–14 and the older single-column
/// (`Pss(KB)`) layout. In both, the first integer after each label is the Pss
/// value, which is what these columns trend. Anything else — the App Summary
/// section absent (`No process found`, a truncated dump), or a header that does
/// not advertise KiB — reads not-measured for every column, never zero.
final class MeminfoSampler implements NativeSampler {
  /// Samples via [_adb], optionally scoped to device [serial].
  const MeminfoSampler(this._adb, {this.serial});

  final AdbRunner _adb;

  /// Target device serial; `null` targets the sole connected device.
  final String? serial;

  static const _columns = {
    TriageColumn.javaHeapKb,
    TriageColumn.nativePssKb,
    TriageColumn.codeKb,
    TriageColumn.graphicsKb,
    TriageColumn.totalPssKb,
  };

  @override
  Set<TriageColumn> get columns => _columns;

  @override
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid) async {
    final result = await _adb.run([
      'shell',
      'dumpsys',
      'meminfo',
      package,
    ], serial: serial);
    if (!result.ok) {
      return allUnmeasured(
        _columns,
        'dumpsys meminfo exited ${result.exitCode}: ${result.stderr.trim()}',
      );
    }
    return parseMeminfoAppSummary(result.stdout);
  }
}

/// Parses the App Summary of raw `dumpsys meminfo` [output] into the five
/// meminfo columns. A label absent from the section reads not-measured for
/// exactly that column; the whole section absent (or not KiB) reads
/// not-measured for all five. Never returns a fabricated zero.
Map<TriageColumn, SampleValue> parseMeminfoAppSummary(String output) {
  final lines = output.split('\n');
  final headerIndex = lines.indexWhere((l) => l.contains('App Summary'));
  if (headerIndex < 0) {
    return allUnmeasured(
      MeminfoSampler._columns,
      'dumpsys meminfo App Summary section not found',
    );
  }

  final endIndex = lines.indexWhere(
    (l) => l.trimLeft().startsWith('Objects'),
    headerIndex + 1,
  );
  final section = lines.sublist(
    headerIndex,
    endIndex < 0 ? lines.length : endIndex,
  );

  if (!section.any((l) => l.toUpperCase().contains('(KB)'))) {
    return allUnmeasured(
      MeminfoSampler._columns,
      'meminfo App Summary is not in KiB (unrecognized unit header)',
    );
  }

  final found = <TriageColumn, int>{};
  for (final line in section) {
    final total = _totalRow.firstMatch(line);
    if (total != null) {
      found[TriageColumn.totalPssKb] = int.parse(total.group(1)!);
      continue;
    }
    final row = _summaryRow.firstMatch(line);
    if (row == null) continue;
    final column = _labelColumns[row.group(1)!.trim()];
    if (column != null) {
      found[column] = int.parse(row.group(2)!);
    }
  }

  return readingsFrom(
    MeminfoSampler._columns,
    found,
    (column) => "meminfo App Summary '${column.name}' not found",
  );
}
