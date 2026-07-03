import 'package:meta/meta.dart';

import '../model/native_callsite.dart';
import '../model/native_frame.dart';
import '../model/native_heap_profile.dart';

/// A JSON-importable map from (module build-id, raw function) to a resolved
/// symbol name, used to upgrade module-only frames to symbolized ones.
///
/// The concrete unstripped-`.so` → symbol-map extraction (`nm`,
/// `llvm-symbolizer`) is host-side tooling and out of scope here; this store
/// only holds and looks up an already-extracted map.
@immutable
final class SymbolStore {
  const SymbolStore(this.byBuildId);

  /// Build-id -> (raw address/function string -> resolved function name).
  final Map<String, Map<String, String>> byBuildId;

  /// True when no build-ids are known.
  bool get isEmpty => byBuildId.isEmpty;

  /// Resolves a frame's function via its module [buildId], or returns null
  /// when the build-id is unknown, `null`, or has no entry for [function].
  String? resolve({required String? buildId, required String function}) {
    if (buildId == null) {
      return null;
    }
    return byBuildId[buildId]?[function];
  }

  Map<String, Object?> toJson() => {
    for (final entry in byBuildId.entries) entry.key: entry.value,
  };

  /// Imports a `{"<buildId>": {"<raw>": "<resolved>"}}` JSON map.
  factory SymbolStore.fromJson(Map<String, Object?> json) => SymbolStore({
    for (final entry in json.entries)
      entry.key: (entry.value as Map).cast<String, String>(),
  });
}

/// Returns a new [NativeHeapProfile] with each frame's `function` replaced by
/// [store]'s resolution when available (matched by the frame's `buildId` and
/// current `function`). Frames with no match are left unchanged — still
/// module-only. Fully immutable: neither [profile] nor its callsites/frames
/// are mutated.
NativeHeapProfile applySymbolStore(
  NativeHeapProfile profile,
  SymbolStore store,
) => NativeHeapProfile(
  capturedAt: profile.capturedAt,
  label: profile.label,
  meta: profile.meta,
  callsites: [
    for (final callsite in profile.callsites)
      NativeCallsite(
        frames: [
          for (final frame in callsite.frames) _resolveFrame(frame, store),
        ],
        allocBytes: callsite.allocBytes,
        allocCount: callsite.allocCount,
        freeBytes: callsite.freeBytes,
        freeCount: callsite.freeCount,
      ),
  ],
);

NativeFrame _resolveFrame(NativeFrame frame, SymbolStore store) {
  final resolved = store.resolve(
    buildId: frame.buildId,
    function: frame.function,
  );
  if (resolved == null) {
    return frame;
  }
  return NativeFrame(
    function: resolved,
    module: frame.module,
    buildId: frame.buildId,
  );
}
