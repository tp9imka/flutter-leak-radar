// lib/src/engine/heap_snapshot_file.dart
import 'dart:developer' as developer;
import 'dart:io';

/// Writes a binary heap snapshot to a file using [developer.NativeRuntime].
///
/// The generated file uses the `.data` extension and is named:
/// `leak_radar_heap_<isoish-timestamp>.data`
///
/// The [directory] argument overrides the destination; it defaults to
/// [Directory.systemTemp] when omitted.
///
/// Returns the absolute path of the written file, or `null` when the platform
/// does not support heap snapshots (e.g. product mode, web, non-standalone VM)
/// or any other error occurs. Never throws.
Future<String?> writeHeapSnapshotFile({
  Directory? directory,
  DateTime Function()? clock,
}) async {
  try {
    final now = (clock ?? DateTime.now)();
    final stamp = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final dir = directory ?? Directory.systemTemp;
    final path = '${dir.path}/leak_radar_heap_$stamp.data';
    developer.NativeRuntime.writeHeapSnapshotToFile(path);
    return path;
  } catch (_) {
    return null;
  }
}
