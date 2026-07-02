import 'package:meta/meta.dart';

import 'native_frame.dart';

/// Still-live growth for one callsite between two heapprofd checkpoints —
/// one row of `diffNativeProfiles`'s Lane B leak ranking.
@immutable
final class NativeAllocationDiff {
  const NativeAllocationDiff({
    required this.signature,
    required this.frames,
    required this.beforeStillLiveBytes,
    required this.afterStillLiveBytes,
    required this.beforeStillLiveCount,
    required this.afterStillLiveCount,
  });

  /// The joined `NativeCallsite.signature` identifying this site across
  /// both checkpoints.
  final String signature;

  /// Stack for this callsite, leaf-first (from the `after` checkpoint).
  final List<NativeFrame> frames;

  /// Still-live bytes at this site in the `before` checkpoint (0 if the
  /// site is new in `after`).
  final int beforeStillLiveBytes;

  /// Still-live bytes at this site in the `after` checkpoint.
  final int afterStillLiveBytes;

  /// Still-live bytes gained between checkpoints — the leak-ranking
  /// signal. Negative when a site shrank.
  int get growthBytes => afterStillLiveBytes - beforeStillLiveBytes;

  /// Still-live allocation count at this site in the `before` checkpoint.
  final int beforeStillLiveCount;

  /// Still-live allocation count at this site in the `after` checkpoint.
  final int afterStillLiveCount;

  /// Still-live allocation count gained between checkpoints.
  int get growthCount => afterStillLiveCount - beforeStillLiveCount;

  Map<String, Object?> toJson() => {
    'signature': signature,
    'frames': [for (final f in frames) f.toJson()],
    'beforeStillLiveBytes': beforeStillLiveBytes,
    'afterStillLiveBytes': afterStillLiveBytes,
    'beforeStillLiveCount': beforeStillLiveCount,
    'afterStillLiveCount': afterStillLiveCount,
  };

  factory NativeAllocationDiff.fromJson(Map<String, Object?> json) =>
      NativeAllocationDiff(
        signature: json['signature'] as String,
        frames: [
          for (final e in (json['frames'] as List? ?? const []))
            NativeFrame.fromJson((e as Map).cast<String, Object?>()),
        ],
        beforeStillLiveBytes: (json['beforeStillLiveBytes'] as num).toInt(),
        afterStillLiveBytes: (json['afterStillLiveBytes'] as num).toInt(),
        beforeStillLiveCount: (json['beforeStillLiveCount'] as num).toInt(),
        afterStillLiveCount: (json['afterStillLiveCount'] as num).toInt(),
      );
}
