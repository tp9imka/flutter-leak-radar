import 'package:radar_native/radar_native.dart';

import '../capture/adb_runner.dart';
import 'sample_snapshot.dart';

/// The estimated-total line, keyed on the `KB` unit token so a differently
/// unitted total refuses rather than mis-scaling.
final _totalAllocated = RegExp(
  r'Total allocated by GraphicBufferAllocator \(estimated\):'
  r'\s*([\d.]+)\s*[Kk]i?B',
);
final _handleRow = RegExp(r'^\s*0x[0-9a-fA-F]+\s*\|');

/// Samples `dumpsys gfxinfo <package>` — the GraphicBufferAllocator total
/// (KiB) and live buffer count.
///
/// Known-good shape (parsed): a `GraphicBufferAllocator buffers:` table whose
/// rows begin with a `0x…` handle, followed by a
/// `Total allocated by GraphicBufferAllocator (estimated): N KB` line. The two
/// columns are measured independently: the count from the table, the KiB total
/// from that line (trusted only when its `KB`/`KiB` unit is present; a foreign
/// unit such as `MB` refuses). Either may read not-measured while the other is
/// measured.
///
/// Boundary: the GraphicBufferAllocator table is not emitted by every build's
/// `dumpsys gfxinfo` — some expose it only via `dumpsys SurfaceFlinger`. When
/// the section is absent (older Android, OEMs that omit it), both columns read
/// not-measured, per the brief — never zero.
final class GfxinfoSampler implements NativeSampler {
  /// Samples via [_adb], optionally scoped to device [serial].
  const GfxinfoSampler(this._adb, {this.serial});

  final AdbRunner _adb;

  /// Target device serial; `null` targets the sole connected device.
  final String? serial;

  static const _columns = {
    TriageColumn.gfxBufferKb,
    TriageColumn.gfxBufferCount,
  };

  @override
  Set<TriageColumn> get columns => _columns;

  @override
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid) async {
    final result = await _adb.run([
      'shell',
      'dumpsys',
      'gfxinfo',
      package,
    ], serial: serial);
    if (!result.ok) {
      return allUnmeasured(
        _columns,
        'dumpsys gfxinfo exited ${result.exitCode}: ${result.stderr.trim()}',
      );
    }
    return parseGfxinfo(result.stdout);
  }
}

/// Parses raw `dumpsys gfxinfo` [output] into the GraphicBufferAllocator KiB
/// total and buffer count. The section absent reads both not-measured; a
/// present table with a missing/foreign-unit total reads the count measured
/// and the KiB not-measured. Never a fabricated zero.
Map<TriageColumn, SampleValue> parseGfxinfo(String output) {
  if (!output.contains('GraphicBufferAllocator')) {
    return allUnmeasured(
      GfxinfoSampler._columns,
      'dumpsys gfxinfo GraphicBufferAllocator section not found',
    );
  }

  final lines = output.split('\n');

  final totalMatch = _totalAllocated.firstMatch(output);
  final kb = totalMatch == null
      ? const SampleValue.unmeasured(
          'GraphicBufferAllocator total not found or not in KiB',
        )
      : SampleValue.measured(double.parse(totalMatch.group(1)!).round());

  final headerIndex = lines.indexWhere(
    (l) => l.contains('GraphicBufferAllocator buffers'),
  );
  final SampleValue count;
  if (headerIndex < 0) {
    count = const SampleValue.unmeasured(
      'GraphicBufferAllocator buffers table not found',
    );
  } else {
    var rows = 0;
    for (var i = headerIndex + 1; i < lines.length; i++) {
      if (lines[i].contains('Total allocated by GraphicBufferAllocator')) break;
      if (_handleRow.hasMatch(lines[i])) rows++;
    }
    count = SampleValue.measured(rows);
  }

  return {TriageColumn.gfxBufferKb: kb, TriageColumn.gfxBufferCount: count};
}
