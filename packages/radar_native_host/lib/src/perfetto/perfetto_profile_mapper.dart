import 'package:radar_native/radar_native.dart';

import 'perfetto_row.dart';

/// Pure mapper: groups rows by `callsiteId`, orders each group by `depth`
/// (leaf-first) into frames, and builds one [NativeCallsite] per callsite.
///
/// No I/O — `source` is an already-materialized `List<PerfettoRow>`; running
/// the actual Perfetto query lives in the host-side parser that owns this
/// mapper.
final class PerfettoProfileMapper implements NativeProfileParser {
  /// [capturedAt] is required: a checkpoint must know its own capture time,
  /// and the facade calling this mapper always has it to hand.
  const PerfettoProfileMapper({
    required this.capturedAt,
    this.meta = const NativeProfileMeta(),
  });

  final DateTime capturedAt;
  final NativeProfileMeta meta;

  @override
  NativeHeapProfile parse(Object source, {String label = ''}) {
    final rows = source as List<PerfettoRow>;
    final byCallsite = <int, List<PerfettoRow>>{};
    for (final row in rows) {
      byCallsite.putIfAbsent(row.callsiteId, () => []).add(row);
    }

    final callsites = [
      for (final group in byCallsite.values) _toCallsite(group),
    ];

    return NativeHeapProfile(
      capturedAt: capturedAt,
      label: label,
      callsites: callsites,
      meta: meta,
    );
  }

  NativeCallsite _toCallsite(List<PerfettoRow> group) {
    final sorted = [...group]..sort((a, b) => a.depth.compareTo(b.depth));
    final first = sorted.first;
    return NativeCallsite(
      frames: [
        for (final row in sorted)
          NativeFrame(
            function: row.function.isNotEmpty
                ? row.function
                : (row.relPc != null
                      ? '0x${row.relPc!.toRadixString(16)}'
                      : ''),
            module: row.module,
            buildId: row.buildId,
          ),
      ],
      allocBytes: first.allocBytes,
      allocCount: first.allocCount,
      freeBytes: first.freeBytes,
      freeCount: first.freeCount,
    );
  }
}
