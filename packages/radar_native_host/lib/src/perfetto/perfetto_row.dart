import 'package:meta/meta.dart';

/// One denormalized row from the still-live query: a single stack frame of a
/// single allocating callsite, carrying that callsite's aggregate accounting.
@immutable
final class PerfettoRow {
  const PerfettoRow({
    required this.callsiteId,
    required this.depth,
    required this.function,
    required this.module,
    this.buildId,
    required this.allocBytes,
    required this.allocCount,
    required this.freeBytes,
    required this.freeCount,
  });

  /// Identifies the callsite this frame belongs to (rows sharing the same
  /// [callsiteId] form one stack).
  final int callsiteId;

  /// Stack depth, 0 = the allocating (leaf) frame.
  final int depth;

  /// Symbolized function name (or empty when unsymbolized).
  final String function;

  /// Owning module (mapping name, e.g. `libflutter.so`).
  final String module;

  /// Build-id of [module], for symbol-store lookup (nullable if unknown).
  final String? buildId;

  final int allocBytes;
  final int allocCount;
  final int freeBytes;
  final int freeCount;

  /// Parses one query result row from its 9 cells, in column order:
  /// `[callsiteId, depth, function, module, buildId, allocBytes, allocCount,
  /// freeBytes, freeCount]`. An empty `buildId` cell maps to `null`; empty
  /// `function`/`module` cells are kept as `''` (unsymbolized frame).
  factory PerfettoRow.fromCells(List<String> cells) => PerfettoRow(
    callsiteId: int.parse(cells[0]),
    depth: int.parse(cells[1]),
    function: cells[2],
    module: cells[3],
    buildId: cells[4].isEmpty ? null : cells[4],
    allocBytes: int.parse(cells[5]),
    allocCount: int.parse(cells[6]),
    freeBytes: int.parse(cells[7]),
    freeCount: int.parse(cells[8]),
  );
}
