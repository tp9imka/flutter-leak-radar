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

final _labelOnly = RegExp(r'^\s*([A-Za-z][A-Za-z /]*?):');
final _totalLabel = RegExp(r'^\s*TOTAL(?: PSS)?:');
final _intToken = RegExp(r'\d+');

/// The integers on [line] after its first `:`, in order, skipping any token
/// too large for [int] (throw-safe: an implausible digit run is dropped, never
/// crashes the sweep).
List<int> _intsAfterColon(String line) {
  final colon = line.indexOf(':');
  final rest = colon < 0 ? line : line.substring(colon + 1);
  return [
    for (final match in _intToken.allMatches(rest))
      if (int.tryParse(match.group(0)!) case final value?) value,
  ];
}

/// Samples the `dumpsys meminfo <package>` App Summary — Java Heap, Native
/// Heap, Code, Graphics, TOTAL PSS.
///
/// Known-good shapes (parsed): the modern two-column App Summary
/// (`Pss(KB)` / `Rss(KB)`) of Android 11–14 and the older single-column
/// (`Pss(KB)`) layout. The Pss value is the first integer on a row, anchored to
/// the `Pss(KB)` column being leftmost (see [parseMeminfoAppSummary]).
/// Anything else — the App Summary section absent (`No process found`, a
/// truncated dump), a header that does not advertise KiB, an Rss-first column
/// order, or a tracked row with a blank Pss cell — reads not-measured, never
/// zero.
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
/// meminfo columns.
///
/// Column anchor: the Pss value is the *first* integer on a row, so the parse
/// is trustworthy only when Pss is the left column. When the header advertises
/// both `Pss(KB)` and `Rss(KB)`, `Pss(KB)` must precede `Rss(KB)` — an
/// Rss-first OEM ordering reads not-measured for all five (`unrecognized column
/// order`) rather than silently reporting Rss as Pss. In that two-column mode a
/// tracked row must carry both cells; a blank Pss cell (only an Rss value
/// present) reads not-measured for that column, never the Rss number
/// mislabelled as Pss.
///
/// A label absent from the section reads not-measured for exactly that column;
/// the whole section absent (or not KiB) reads not-measured for all five. Never
/// returns a fabricated zero.
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

  final sectionUpper = section.join('\n').toUpperCase();
  if (!sectionUpper.contains('(KB)')) {
    return allUnmeasured(
      MeminfoSampler._columns,
      'meminfo App Summary is not in KiB (unrecognized unit header)',
    );
  }

  final pssPos = sectionUpper.indexOf('PSS(KB)');
  final rssPos = sectionUpper.indexOf('RSS(KB)');
  final twoColumn = pssPos >= 0 && rssPos >= 0;
  if (twoColumn && pssPos > rssPos) {
    return allUnmeasured(
      MeminfoSampler._columns,
      'meminfo App Summary unrecognized column order (Rss precedes Pss)',
    );
  }

  final found = <TriageColumn, int>{};
  final blankPss = <TriageColumn>{};
  for (final line in section) {
    if (_totalLabel.hasMatch(line)) {
      // TOTAL PSS is explicitly labelled, so its first integer is always the
      // Pss total regardless of column count.
      final ints = _intsAfterColon(line);
      if (ints.isNotEmpty) found[TriageColumn.totalPssKb] = ints.first;
      continue;
    }
    final labelMatch = _labelOnly.firstMatch(line);
    if (labelMatch == null) continue;
    final column = _labelColumns[labelMatch.group(1)!.trim()];
    if (column == null) continue;
    final ints = _intsAfterColon(line);
    if (twoColumn && ints.length < 2) {
      // Two-column layout but only one cell present: the Pss cell is blank and
      // the lone integer is Rss — refuse rather than mislabel it as Pss.
      blankPss.add(column);
      continue;
    }
    if (ints.isNotEmpty) found[column] = ints.first;
  }

  return readingsFrom(
    MeminfoSampler._columns,
    found,
    (column) => blankPss.contains(column)
        ? "meminfo App Summary '${column.name}' Pss cell is blank"
        : "meminfo App Summary '${column.name}' not found",
  );
}
