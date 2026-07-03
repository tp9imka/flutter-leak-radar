import '../model/native_allocation_diff.dart';
import '../model/native_heap_profile.dart';

/// Ranks what grew in still-live bytes between two heapprofd checkpoints —
/// the Lane B leak signal (no GC roots; growth in never-freed bytes). Joins
/// callsites by [NativeCallsite.signature]; a site absent from [before] reads
/// as a zero baseline (matching leak_graph's computeDiff). When
/// [includeRemoved] is true, sites present in [before] but absent from
/// [after] are also appended, with a zero `after` baseline, so callers can
/// surface them as GONE rows. Sorted by growth bytes descending, tie-broken
/// by [NativeAllocationDiff.signature] ascending for determinism.
List<NativeAllocationDiff> diffNativeProfiles(
  NativeHeapProfile before,
  NativeHeapProfile after, {
  bool includeRemoved = false,
}) {
  final beforeBySig = {for (final c in before.callsites) c.signature: c};
  final afterSigs = {for (final a in after.callsites) a.signature};
  final diffs =
      <NativeAllocationDiff>[
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
        if (includeRemoved)
          for (final b in before.callsites)
            if (!afterSigs.contains(b.signature))
              NativeAllocationDiff(
                signature: b.signature,
                frames: b.frames,
                beforeStillLiveBytes: b.stillLiveBytes,
                afterStillLiveBytes: 0,
                beforeStillLiveCount: b.stillLiveCount,
                afterStillLiveCount: 0,
              ),
      ]..sort((x, y) {
        final g = y.growthBytes.compareTo(x.growthBytes);
        return g != 0 ? g : x.signature.compareTo(y.signature);
      });
  return diffs;
}
