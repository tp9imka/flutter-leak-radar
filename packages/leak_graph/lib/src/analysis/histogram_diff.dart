import '../model/class_count.dart';

/// Per-class growth delta between two heap snapshots.
///
/// Produced by [computeDiff]; carries the before/after [ClassCount] so callers
/// can access all fields of both snapshots alongside the derived deltas.
final class ClassCountDiff {
  final ClassCount before;
  final ClassCount after;

  /// Positive = class grew; negative = class shrank; zero = unchanged.
  int get instanceDelta => after.instanceCount - before.instanceCount;

  /// Positive = more shallow bytes; negative = fewer; zero = unchanged.
  int get bytesDelta => after.shallowBytes - before.shallowBytes;

  const ClassCountDiff({required this.before, required this.after});

  /// Encodes the diff plus its derived deltas.
  ///
  /// The [instanceDelta]/[bytesDelta] are serialized (not just the before/after
  /// counts) so a CI consumer reads the growth verdict directly without
  /// recomputing it — the numbers in the JSON are the numbers that were
  /// measured.
  Map<String, Object?> toJson() => {
    'className': after.className,
    'before': before.toJson(),
    'after': after.toJson(),
    'instanceDelta': instanceDelta,
    'bytesDelta': bytesDelta,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassCountDiff && before == other.before && after == other.after;

  @override
  int get hashCode => Object.hash(before, after);
}

/// Serialization version stamped into [encodeDiffReport].
const int kClassCountDiffReportSchemaVersion = 1;

/// Wraps a list of [ClassCountDiff] in a schema-stamped JSON-ready envelope.
///
/// Emitted by the `diff` CLI. The `schemaVersion` lets a reader refuse a newer
/// major format instead of silently mis-parsing it.
Map<String, Object?> encodeDiffReport(List<ClassCountDiff> diffs) => {
  'schemaVersion': kClassCountDiffReportSchemaVersion,
  'diffs': [for (final d in diffs) d.toJson()],
};

/// Diffs two class histograms and returns per-class deltas sorted by
/// [ClassCountDiff.instanceDelta] descending (largest grower first).
///
/// Classes in [after] with no matching entry in [before] get a zero-count
/// synthetic baseline so new classes show their full count as growth.
/// Classes absent from [after] are omitted (they are gone, not leaked).
///
/// Matching is by [ClassCount.className] only — library URIs may differ
/// between snapshots after hot-reload but the class is the same thing.
List<ClassCountDiff> computeDiff(
  List<ClassCount> before,
  List<ClassCount> after,
) {
  final beforeByName = <String, ClassCount>{
    for (final c in before) c.className: c,
  };

  final diffs = <ClassCountDiff>[];
  for (final afterEntry in after) {
    final beforeEntry = beforeByName[afterEntry.className];
    final syntheticBefore =
        beforeEntry ??
        ClassCount(
          className: afterEntry.className,
          libraryUri: afterEntry.libraryUri,
          instanceCount: 0,
          shallowBytes: 0,
        );
    diffs.add(ClassCountDiff(before: syntheticBefore, after: afterEntry));
  }

  diffs.sort((a, b) => b.instanceDelta.compareTo(a.instanceDelta));
  return diffs;
}
