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
  flat,
}

/// Derives a [NativeDiffStatus] from a [NativeAllocationDiff]'s still-live
/// byte counts.
extension NativeAllocationDiffStatus on NativeAllocationDiff {
  /// Classifies this row. Checked in order: `added` (new site), `gone`
  /// (removed site), then by the sign of [NativeAllocationDiff.growthBytes].
  NativeDiffStatus get status {
    if (beforeStillLiveBytes == 0 && afterStillLiveBytes > 0) {
      return NativeDiffStatus.added;
    }
    if (afterStillLiveBytes == 0 && beforeStillLiveBytes > 0) {
      return NativeDiffStatus.gone;
    }
    if (growthBytes > 0) return NativeDiffStatus.grew;
    if (growthBytes < 0) return NativeDiffStatus.shrank;
    return NativeDiffStatus.flat;
  }
}
