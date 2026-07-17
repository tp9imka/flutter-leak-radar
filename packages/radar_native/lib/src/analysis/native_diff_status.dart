import '../model/native_allocation_diff.dart';

/// Classification of a [NativeAllocationDiff] row for display (e.g. the
/// Android Compare view's ADDED/GREW/SHRANK/GONE badges).
enum NativeDiffStatus {
  /// Absent from `before`, present in `after`.
  added,

  /// Grew in still-live bytes between checkpoints.
  grew,

  /// Shrank in still-live bytes between checkpoints.
  shrank,

  /// Present in `before`, absent from `after`.
  gone,

  /// No change in still-live bytes.
  flat;

  /// Serialises to its stable enum name.
  String toJson() => name;

  /// Restores from a [toJson] name. Throws [FormatException] on an unknown
  /// name — a corrupt status must not silently read as `flat`.
  static NativeDiffStatus fromJson(String name) {
    final status = NativeDiffStatus.values.asNameMap()[name];
    if (status == null) {
      throw FormatException('unknown NativeDiffStatus name: $name');
    }
    return status;
  }
}

/// Classifies a before/after still-live byte pair. Shared by
/// [NativeAllocationDiff.status] (per-callsite) and `NativeModuleDiff.status`
/// (per-module) so the two rollups never drift apart. Checked in order:
/// `added` (new site), `gone` (removed site), then by the sign of the
/// after-minus-before delta.
NativeDiffStatus nativeDiffStatus(int beforeBytes, int afterBytes) {
  if (beforeBytes == 0 && afterBytes > 0) return NativeDiffStatus.added;
  if (afterBytes == 0 && beforeBytes > 0) return NativeDiffStatus.gone;
  final growth = afterBytes - beforeBytes;
  if (growth > 0) return NativeDiffStatus.grew;
  if (growth < 0) return NativeDiffStatus.shrank;
  return NativeDiffStatus.flat;
}

/// Derives a [NativeDiffStatus] from a [NativeAllocationDiff]'s still-live
/// byte counts.
extension NativeAllocationDiffStatus on NativeAllocationDiff {
  /// Classifies this row via [nativeDiffStatus].
  NativeDiffStatus get status =>
      nativeDiffStatus(beforeStillLiveBytes, afterStillLiveBytes);
}
