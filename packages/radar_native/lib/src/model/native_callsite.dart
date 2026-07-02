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

  /// Stable identity for cross-checkpoint diffing: the (leaf-first) frames,
  /// each rendered as `module<US>function` (U+001F unit separator between
  /// module and function) and the frames joined by `<NUL>` (U+0000).
  /// Symbolized C++/Rust names routinely contain `>`, `::`, and `|` (e.g.
  /// `std::vector<int>::push_back`), so a printable delimiter like the
  /// original `>`/`|` scheme can let distinct stacks collide onto the same
  /// signature; these control characters never appear in symbol names or
  /// module paths, so they can't. Two checkpoints' callsites with the same
  /// signature are "the same site".
  String get signature =>
      frames.map((f) => '${f.module}\u001F${f.function}').join('\u0000');

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
