import 'package:meta/meta.dart';

/// One still-live FFI allocation site (Lane D): every not-yet-freed block
/// sharing the same leaf Dart stack frame, aggregated together.
///
/// Produced by grouping the Spike-3 `LoggingAllocator` dump's raw records —
/// see `JsonFfiAllocationLogParser`. Because the allocator only ever dumps
/// blocks it hasn't freed, every record feeding this model is already
/// still-live; there is no alloc/free subtraction here (unlike
/// `NativeCallsite`'s Lane B heapprofd accounting).
@immutable
final class FfiAllocationSite {
  const FfiAllocationSite({
    required this.site,
    required this.file,
    required this.stillLiveBytes,
    required this.stillLiveBlocks,
    required this.dartStack,
  });

  /// Function part of the leaf stack frame, e.g. `'ImageCodec.decode'`.
  final String site;

  /// `file:line` part of the leaf stack frame, e.g. `'image_codec.dart:88'`.
  /// Empty when the leaf frame had no whitespace separator to split on.
  final String file;

  /// Summed `byteCount` of every record grouped into this site.
  final int stillLiveBytes;

  /// Number of records grouped into this site.
  final int stillLiveBlocks;

  /// One representative record's stack, leaf-first (`'Function  file.dart:line'`).
  final List<String> dartStack;

  Map<String, Object?> toJson() => {
    'site': site,
    'file': file,
    'stillLiveBytes': stillLiveBytes,
    'stillLiveBlocks': stillLiveBlocks,
    'dartStack': dartStack,
  };

  factory FfiAllocationSite.fromJson(Map<String, Object?> json) =>
      FfiAllocationSite(
        site: json['site'] as String,
        file: json['file'] as String,
        stillLiveBytes: (json['stillLiveBytes'] as num).toInt(),
        stillLiveBlocks: (json['stillLiveBlocks'] as num).toInt(),
        dartStack: [
          for (final e in (json['dartStack'] as List? ?? const [])) e as String,
        ],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FfiAllocationSite &&
          site == other.site &&
          file == other.file &&
          stillLiveBytes == other.stillLiveBytes &&
          stillLiveBlocks == other.stillLiveBlocks &&
          _listEquals(dartStack, other.dartStack);

  @override
  int get hashCode => Object.hash(
    site,
    file,
    stillLiveBytes,
    stillLiveBlocks,
    Object.hashAll(dartStack),
  );
}

/// One ffi-lane (Lane D) import: every still-live FFI allocation site
/// captured by a single `LoggingAllocator` dump.
@immutable
final class FfiAllocationLog {
  const FfiAllocationLog({required this.capturedAt, required this.sites});

  /// When the underlying `LoggingAllocator` dump was captured.
  final DateTime capturedAt;

  /// Every still-live allocation site observed in this dump.
  final List<FfiAllocationSite> sites;

  /// Total still-live bytes across all sites.
  int get totalStillLiveBytes =>
      sites.fold(0, (sum, s) => sum + s.stillLiveBytes);

  Map<String, Object?> toJson() => {
    'version': 1,
    'capturedAt': capturedAt.toIso8601String(),
    'sites': [for (final s in sites) s.toJson()],
  };

  /// Tolerant of a missing `sites` list: defaults to empty rather than
  /// throwing, mirroring `NativeHeapProfile.fromJson`.
  factory FfiAllocationLog.fromJson(Map<String, Object?> json) =>
      FfiAllocationLog(
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        sites: [
          for (final e in (json['sites'] as List? ?? const []))
            FfiAllocationSite.fromJson((e as Map).cast<String, Object?>()),
        ],
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
