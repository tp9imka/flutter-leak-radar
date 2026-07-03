import 'package:meta/meta.dart';

import '../model/native_heap_profile.dart';
import 'native_diff_status.dart';
import 'native_module_kind.dart';
import 'native_module_summary.dart';

/// Per-module still-live rollup diff between two heapprofd checkpoints — the
/// per-MODULE row backing the Compare view, a peer to the per-callsite
/// `NativeAllocationDiff`.
@immutable
final class NativeModuleDiff {
  const NativeModuleDiff({
    required this.module,
    required this.kind,
    required this.beforeStillLiveBytes,
    required this.afterStillLiveBytes,
  });

  /// Short display name of the module (see [NativeModuleSummary.module]).
  final String module;

  /// UI color-kind bucket, preferring the `after` checkpoint's mapping.
  final NativeModuleKind kind;

  /// Still-live bytes for this module in the `before` checkpoint (0 if the
  /// module is new in `after`).
  final int beforeStillLiveBytes;

  /// Still-live bytes for this module in the `after` checkpoint (0 if the
  /// module is gone by `after`).
  final int afterStillLiveBytes;

  /// Still-live bytes gained between checkpoints. Negative when a module
  /// shrank.
  int get deltaBytes => afterStillLiveBytes - beforeStillLiveBytes;

  /// Classifies this row via [nativeDiffStatus].
  NativeDiffStatus get status =>
      nativeDiffStatus(beforeStillLiveBytes, afterStillLiveBytes);
}

/// Joins two checkpoints' per-module rollups ([summarizeByModule]) by module
/// name for the Compare view. Modules present in only one side get 0 on the
/// other; `kind` prefers the `after` side's mapping, falling back to
/// `before` when the module is gone by `after`. Sorted by
/// [NativeModuleDiff.deltaBytes] magnitude descending, tie-broken by module
/// name ascending.
List<NativeModuleDiff> diffModuleSummaries(
  NativeHeapProfile before,
  NativeHeapProfile after,
) {
  final beforeByModule = {
    for (final s in summarizeByModule(before)) s.module: s,
  };
  final afterByModule = {for (final s in summarizeByModule(after)) s.module: s};
  final modules = {...beforeByModule.keys, ...afterByModule.keys};

  final diffs =
      [
        for (final module in modules)
          NativeModuleDiff(
            module: module,
            kind: afterByModule[module]?.kind ?? beforeByModule[module]!.kind,
            beforeStillLiveBytes: beforeByModule[module]?.stillLiveBytes ?? 0,
            afterStillLiveBytes: afterByModule[module]?.stillLiveBytes ?? 0,
          ),
      ]..sort((a, b) {
        final delta = b.deltaBytes.abs().compareTo(a.deltaBytes.abs());
        return delta != 0 ? delta : a.module.compareTo(b.module);
      });
  return diffs;
}
