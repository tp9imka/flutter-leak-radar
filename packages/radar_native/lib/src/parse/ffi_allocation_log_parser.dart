import 'dart:convert';

import '../model/ffi_allocation_log.dart';

/// Converts a raw ffi-lane (Lane D) allocation dump into an
/// [FfiAllocationLog].
abstract interface class FfiAllocationLogParser {
  /// Parses [source] into an [FfiAllocationLog].
  FfiAllocationLog parse(Object source);
}

/// Parses the Spike-3 `LoggingAllocator` dump: a JSON string of
/// `{"capturedAt": (an ISO-8601 string), "records": [{"address": (an int),
/// "byteCount": (an int), "stack": ["Frame  file.dart:line", ...]
/// (leaf-first), "timestamp": (an ISO-8601 string)}, ...]}`.
///
/// The allocator only ever dumps blocks it hasn't freed yet, so every
/// record here is already still-live; this parser's job is purely to GROUP
/// those records by their leaf Dart stack frame into [FfiAllocationSite]s,
/// summing bytes and counting blocks per site.
final class JsonFfiAllocationLogParser implements FfiAllocationLogParser {
  const JsonFfiAllocationLogParser();

  @override
  FfiAllocationLog parse(Object source) {
    final decoded = (jsonDecode(source as String) as Map)
        .cast<String, Object?>();
    final records = [
      for (final e in (decoded['records'] as List? ?? const []))
        (e as Map).cast<String, Object?>(),
    ];

    final byLeaf = <String, List<Map<String, Object?>>>{};
    for (final record in records) {
      final leaf = _leafFrame(record);
      byLeaf.putIfAbsent(leaf, () => []).add(record);
    }

    return FfiAllocationLog(
      capturedAt: DateTime.parse(decoded['capturedAt'] as String),
      sites: [
        for (final entry in byLeaf.entries) _toSite(entry.key, entry.value),
      ],
    );
  }

  String _leafFrame(Map<String, Object?> record) {
    final stack = record['stack'] as List? ?? const [];
    return stack.isEmpty ? '' : stack.first as String;
  }

  FfiAllocationSite _toSite(String leaf, List<Map<String, Object?>> group) {
    final split = _splitLeafFrame(leaf);
    final dartStack = [
      for (final frame in (group.first['stack'] as List? ?? const []))
        frame as String,
    ];
    final stillLiveBytes = group.fold<int>(
      0,
      (sum, record) => sum + ((record['byteCount'] as num?)?.toInt() ?? 0),
    );

    return FfiAllocationSite(
      site: split.site,
      file: split.file,
      stillLiveBytes: stillLiveBytes,
      stillLiveBlocks: group.length,
      dartStack: dartStack,
    );
  }
}

/// Splits a leaf stack frame like `'Foo.bar  foo.dart:12'` into its
/// function ([site]) and `file:line` ([file]) parts, on the first run of
/// whitespace. A frame with no whitespace puts everything in [site] and
/// leaves [file] empty.
({String site, String file}) _splitLeafFrame(String frame) {
  final match = RegExp(r'\s+').firstMatch(frame);
  if (match == null) return (site: frame, file: '');
  return (
    site: frame.substring(0, match.start),
    file: frame.substring(match.end),
  );
}
