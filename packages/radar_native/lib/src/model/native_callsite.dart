import 'package:meta/meta.dart';

import 'native_frame.dart';

/// A leaf callsite with its stack and aggregated allocation accounting from a
/// single heapprofd checkpoint. Still-live = alloc − free is the Lane B leak
/// signal (no GC: what was allocated and never freed).
@immutable
final class NativeCallsite {
  const NativeCallsite({
    required this.frames,
    required this.allocBytes,
    required this.allocCount,
    required this.freeBytes,
    required this.freeCount,
  });

  /// Stack for this callsite, leaf-first (index 0 = the allocating frame).
  final List<NativeFrame> frames;

  final int allocBytes;
  final int allocCount;
  final int freeBytes;
  final int freeCount;

  /// Bytes allocated here and not yet freed — the leak signal.
  int get stillLiveBytes => allocBytes - freeBytes;

  /// Allocations here not yet freed.
  int get stillLiveCount => allocCount - freeCount;

  /// Stable identity for cross-checkpoint diffing: `module>function` over the
  /// (leaf-first) frames. Two checkpoints' callsites with the same signature
  /// are "the same site".
  String get signature =>
      frames.map((f) => '${f.module}>${f.function}').join('|');

  Map<String, Object?> toJson() => {
    'frames': [for (final f in frames) f.toJson()],
    'allocBytes': allocBytes,
    'allocCount': allocCount,
    'freeBytes': freeBytes,
    'freeCount': freeCount,
  };

  factory NativeCallsite.fromJson(Map<String, Object?> json) => NativeCallsite(
    frames: [
      for (final e in (json['frames'] as List? ?? const []))
        NativeFrame.fromJson((e as Map).cast<String, Object?>()),
    ],
    allocBytes: (json['allocBytes'] as num).toInt(),
    allocCount: (json['allocCount'] as num).toInt(),
    freeBytes: (json['freeBytes'] as num).toInt(),
    freeCount: (json['freeCount'] as num).toInt(),
  );
}
