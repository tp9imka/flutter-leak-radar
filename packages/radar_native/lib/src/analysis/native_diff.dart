import '../model/native_allocation_diff.dart';
import '../model/native_heap_profile.dart';

/// Ranks what grew in still-live bytes between two heapprofd checkpoints —
/// the Lane B leak signal (no GC roots; growth in never-freed bytes). Joins
/// callsites by [NativeCallsite.signature]; a site absent from [before] reads
/// as a zero baseline (matching leak_graph's computeDiff). Sorted by growth
/// bytes, descending.
List<NativeAllocationDiff> diffNativeProfiles(
  NativeHeapProfile before,
  NativeHeapProfile after,
) {
  final beforeBySig = {for (final c in before.callsites) c.signature: c};
  final diffs = <NativeAllocationDiff>[
    for (final a in after.callsites)
      () {
        final b = beforeBySig[a.signature];
        return NativeAllocationDiff(
          signature: a.signature,
          frames: a.frames,
          beforeStillLiveBytes: b?.stillLiveBytes ?? 0,
          afterStillLiveBytes: a.stillLiveBytes,
          beforeStillLiveCount: b?.stillLiveCount ?? 0,
          afterStillLiveCount: a.stillLiveCount,
        );
      }(),
  ]..sort((x, y) => y.growthBytes.compareTo(x.growthBytes));
  return diffs;
}
