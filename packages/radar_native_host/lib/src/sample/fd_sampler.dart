import 'package:radar_native/radar_native.dart';

import '../capture/adb_runner.dart';
import 'sample_snapshot.dart';

/// Samples `ls -l /proc/<pid>/fd` — total open descriptors plus the
/// graphics/IPC-relevant classes (`sync_file`, `dmabuf`, `ashmem`).
///
/// Known-good shape (parsed): `ls -l` symlink lines whose target follows
/// ` -> `. Targets are classified by substring so OEM/kernel spelling variance
/// is tolerated: `anon_inode:sync_file` and `anon_inode:[sync_file]`;
/// `/dmabuf:...` and `anon_inode:dmabuf`; `/dev/ashmem` and
/// `/dev/ashmem/<region>`. The `total N` header and any non-symlink line are
/// ignored.
///
/// Classification boundary (documented, not a bug): the class counts are
/// *name-based* and deliberately narrow. Two real variants sit outside them
/// and count only toward [TriageColumn.fdTotal], never mislabelled into a
/// class:
/// - Vendor GPU descriptors (Adreno `/dev/kgsl-3d0`, Mali `/dev/mali0`) back
///   graphics memory but are not named `dmabuf`, so they are not counted as
///   dmabuf — folding them in would be a mislabel.
/// - On Android 11+ shared memory migrated from ashmem to `memfd:` — those
///   descriptors are not `ashmem` and are not counted as such.
/// `fdTotal` is the leak safety-net that still trends both: a descriptor leak
/// shows in the total even when its class is not one this sampler names.
///
/// Measured-zero vs not-measured: once at least one descriptor is read, the
/// total and every class are measured — a class count of `0` is a genuine "saw
/// the table, none matched", not a miss. Only when *no* descriptor line can be
/// read (dead pid, permission denied, `No such file`) do all four columns read
/// not-measured. A real process always has fds 0/1/2, so an empty listing is
/// itself the failure signal.
final class FdSampler implements NativeSampler {
  /// Samples via [_adb], optionally scoped to device [serial].
  const FdSampler(this._adb, {this.serial});

  final AdbRunner _adb;

  /// Target device serial; `null` targets the sole connected device.
  final String? serial;

  static const _columns = {
    TriageColumn.fdTotal,
    TriageColumn.fdSyncFile,
    TriageColumn.fdDmabuf,
    TriageColumn.fdAshmem,
  };

  @override
  Set<TriageColumn> get columns => _columns;

  @override
  Future<Map<TriageColumn, SampleValue>> sample(String package, int pid) async {
    final result = await _adb.run([
      'shell',
      'ls',
      '-l',
      '/proc/$pid/fd',
    ], serial: serial);
    if (!result.ok) {
      return allUnmeasured(
        _columns,
        'ls -l /proc/$pid/fd exited ${result.exitCode}: '
        '${result.stderr.trim()}',
      );
    }
    return parseFdList(result.stdout);
  }
}

/// Parses `ls -l /proc/<pid>/fd` [output] into fd counts. An empty listing
/// (no ` -> ` symlink target on any line) reads not-measured for all four
/// columns — never a fabricated zero. Otherwise all four are measured, with a
/// class count of `0` a legitimate measured zero.
Map<TriageColumn, SampleValue> parseFdList(String output) {
  final targets = <String>[];
  for (final line in output.split('\n')) {
    final arrow = line.indexOf(' -> ');
    if (arrow < 0) continue;
    targets.add(line.substring(arrow + 4));
  }
  if (targets.isEmpty) {
    return allUnmeasured(
      FdSampler._columns,
      'no file descriptors listed (dead pid or unreadable /proc/<pid>/fd)',
    );
  }

  var syncFile = 0;
  var dmabuf = 0;
  var ashmem = 0;
  for (final target in targets) {
    if (target.contains('sync_file')) syncFile++;
    if (target.contains('dmabuf')) dmabuf++;
    if (target.contains('ashmem')) ashmem++;
  }

  return {
    TriageColumn.fdTotal: SampleValue.measured(targets.length),
    TriageColumn.fdSyncFile: SampleValue.measured(syncFile),
    TriageColumn.fdDmabuf: SampleValue.measured(dmabuf),
    TriageColumn.fdAshmem: SampleValue.measured(ashmem),
  };
}
