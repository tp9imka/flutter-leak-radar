import 'package:meta/meta.dart';
import 'package:radar_trace/radar_trace.dart';

import 'triage_timeline.dart';

/// Unit family of a [TriageColumn]. Slopes are only ever ranked *within* a
/// family: bytes columns compare in their byte unit per hour, count columns
/// in units per hour. A byte rate and a count rate are never cross-compared.
enum TriageColumnFamily {
  /// A memory size (measured in KiB by the Lane A columns).
  bytes,

  /// A cardinality (threads, file descriptors, GPU buffers).
  count,
}

/// The leak bucket a growing column attributes to — the router's verdict
/// names exactly one of these (or [none] when nothing grows / nothing can be
/// attributed).
enum TriageBucket {
  /// ART/Java managed heap growth.
  javaHeap,

  /// Native (jemalloc) heap growth — malloc/new not freed.
  nativeMalloc,

  /// memtrack / GPU graphics-buffer growth.
  graphics,

  /// Mapped code (.so/.dex/.oat) growth.
  code,

  /// File-descriptor growth.
  fd,

  /// Thread-count growth.
  thread,

  /// No growing bucket could be attributed.
  none,
}

/// The unit family of [column].
TriageColumnFamily columnFamily(TriageColumn column) => switch (column) {
  TriageColumn.javaHeapKb ||
  TriageColumn.nativePssKb ||
  TriageColumn.graphicsKb ||
  TriageColumn.codeKb ||
  TriageColumn.totalPssKb ||
  TriageColumn.rssAnonKb ||
  TriageColumn.vmRssKb ||
  TriageColumn.gfxBufferKb => TriageColumnFamily.bytes,
  TriageColumn.threads ||
  TriageColumn.fdTotal ||
  TriageColumn.fdSyncFile ||
  TriageColumn.fdDmabuf ||
  TriageColumn.fdAshmem ||
  TriageColumn.gfxBufferCount => TriageColumnFamily.count,
};

/// The leak bucket [column] attributes to.
///
/// `totalPssKb`/`vmRssKb` are aggregates that corroborate but never isolate a
/// leak, so they map to [TriageBucket.none] — the router treats them as
/// never-primary corroboration.
TriageBucket columnBucket(TriageColumn column) => switch (column) {
  TriageColumn.javaHeapKb => TriageBucket.javaHeap,
  TriageColumn.nativePssKb ||
  TriageColumn.rssAnonKb => TriageBucket.nativeMalloc,
  TriageColumn.graphicsKb ||
  TriageColumn.gfxBufferKb ||
  TriageColumn.gfxBufferCount => TriageBucket.graphics,
  TriageColumn.codeKb => TriageBucket.code,
  TriageColumn.fdTotal ||
  TriageColumn.fdSyncFile ||
  TriageColumn.fdDmabuf ||
  TriageColumn.fdAshmem => TriageBucket.fd,
  TriageColumn.threads => TriageBucket.thread,
  TriageColumn.totalPssKb || TriageColumn.vmRssKb => TriageBucket.none,
};

/// Whether [column] can be named as a verdict's primary bucket. Aggregate
/// corroborating columns cannot.
bool isPrimaryColumn(TriageColumn column) =>
    columnBucket(column) != TriageBucket.none;

/// One column's [SeriesAssessment], tagged with the column it came from.
@immutable
final class TriageColumnAssessment {
  /// The assessed column.
  final TriageColumn column;

  /// The column's series assessment (verdict + slopes + honest detail).
  final SeriesAssessment assessment;

  /// Pairs [column] with its [assessment].
  const TriageColumnAssessment({
    required this.column,
    required this.assessment,
  });

  /// Restores from [toJson] output. Throws [FormatException] on an unknown
  /// column name.
  factory TriageColumnAssessment.fromJson(Map<String, Object?> json) {
    final name = json['column'] as String;
    final column = TriageColumn.values.asNameMap()[name];
    if (column == null) {
      throw FormatException('unknown TriageColumn name: $name');
    }
    return TriageColumnAssessment(
      column: column,
      assessment: SeriesAssessment.fromJson(
        (json['assessment'] as Map).cast<String, Object?>(),
      ),
    );
  }

  /// Serialises to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'column': column.name,
    'assessment': assessment.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TriageColumnAssessment &&
          column == other.column &&
          assessment == other.assessment;

  @override
  int get hashCode => Object.hash(column, assessment);

  @override
  String toString() => 'TriageColumnAssessment($column, $assessment)';
}

/// The router verdict: the dominant growing [bucket], every measured column's
/// [assessments], and one honest [summary] sentence.
@immutable
final class TriageVerdict {
  /// The JSON schema version written by [toJson].
  static const int schemaVersion = 1;

  /// The dominant growing bucket; [TriageBucket.none] when nothing grows or
  /// no deterministic column isolates a bucket.
  final TriageBucket bucket;

  /// Every measured column's assessment, in [TriageColumn] declaration order.
  final List<TriageColumnAssessment> assessments;

  /// One honest sentence: the named bucket + rate, `'no monotonic growth
  /// detected'`, or an `'insufficient data: …'` listing.
  final String summary;

  /// Creates a verdict.
  const TriageVerdict({
    required this.bucket,
    required this.assessments,
    required this.summary,
  });

  /// Serialises to a JSON-encodable map carrying `'schemaVersion': 1`.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'bucket': bucket.name,
    'assessments': [for (final a in assessments) a.toJson()],
    'summary': summary,
  };

  @override
  String toString() => 'TriageVerdict(${bucket.name}: $summary)';
}

/// Routes a [TriageTimeline] to a bucket verdict.
///
/// Assesses every measured column, then ranks the growing ones
/// ([SeriesVerdict.monotonicGrowth] with a positive slope) *within* their
/// unit family — byte rates and count rates are never cross-compared. The
/// dominant growing bytes bucket is primary; if only count columns grow, the
/// dominant count bucket is primary. Every other growing bucket is named in
/// the summary, so no growing signal is dropped.
///
/// Honesty contract:
/// - A bucket is named only when a primary-eligible column in it shows
///   monotonic growth — never inferred from a plateau, noisy, or
///   insufficient-data column.
/// - `totalPssKb`/`vmRssKb` corroborate but are never primary; growth seen
///   only there yields [TriageBucket.none] while still surfacing that
///   aggregate growth (never silently dropped).
/// - Columns that assess as [SeriesVerdict.insufficientData] are listed in
///   the summary as not-measured — never counted as flat. Columns absent from
///   the timeline are never assessed at all.
TriageVerdict triage(
  TriageTimeline timeline, [
  AssessOptions options = const AssessOptions(),
]) {
  final assessments = <TriageColumnAssessment>[];
  for (final column in TriageColumn.values) {
    final series = timeline.columns[column];
    if (series == null) continue;
    assessments.add(
      TriageColumnAssessment(
        column: column,
        assessment: assessSeries(series, options),
      ),
    );
  }

  double slopeOf(TriageColumnAssessment a) => a.assessment.slopePerHour ?? 0;
  bool isGrowing(TriageColumnAssessment a) =>
      a.assessment.verdict == SeriesVerdict.monotonicGrowth && slopeOf(a) > 0;

  final growing = [
    for (final a in assessments)
      if (isGrowing(a)) a,
  ];

  // Rank within family; bytes and count rates are never compared to each
  // other, so bytes always takes primary when any bytes bucket grows.
  final bytesGrowers = [
    for (final a in growing)
      if (columnFamily(a.column) == TriageColumnFamily.bytes &&
          isPrimaryColumn(a.column))
        a,
  ]..sort((x, y) => slopeOf(y).compareTo(slopeOf(x)));
  final countGrowers = [
    for (final a in growing)
      if (columnFamily(a.column) == TriageColumnFamily.count) a,
  ]..sort((x, y) => slopeOf(y).compareTo(slopeOf(x)));

  final TriageColumnAssessment? primary = bytesGrowers.isNotEmpty
      ? bytesGrowers.first
      : (countGrowers.isNotEmpty ? countGrowers.first : null);
  final bucket = primary == null
      ? TriageBucket.none
      : columnBucket(primary.column);

  final unitByColumn = {
    for (final entry in timeline.columns.entries) entry.key: entry.value.unit,
  };
  String rate(TriageColumnAssessment a) {
    final unit = unitByColumn[a.column] ?? '';
    return '~${_fmtRate(slopeOf(a))} $unit/h';
  }

  final insufficient = [
    for (final a in assessments)
      if (a.assessment.verdict == SeriesVerdict.insufficientData) a.column,
  ];
  final insufficientClause = insufficient.isEmpty
      ? null
      : 'insufficient data: ${insufficient.map((c) => c.name).join(', ')}';

  final corroborating = [
    for (final a in growing)
      if (!isPrimaryColumn(a.column)) a,
  ];

  final summary = _summarize(
    primary: primary,
    bucket: bucket,
    bytesGrowers: bytesGrowers,
    countGrowers: countGrowers,
    corroborating: corroborating,
    rate: rate,
    insufficientClause: insufficientClause,
    measuredCount: assessments.length,
    insufficientCount: insufficient.length,
  );

  return TriageVerdict(
    bucket: bucket,
    assessments: assessments,
    summary: summary,
  );
}

String _summarize({
  required TriageColumnAssessment? primary,
  required TriageBucket bucket,
  required List<TriageColumnAssessment> bytesGrowers,
  required List<TriageColumnAssessment> countGrowers,
  required List<TriageColumnAssessment> corroborating,
  required String Function(TriageColumnAssessment) rate,
  required String? insufficientClause,
  required int measuredCount,
  required int insufficientCount,
}) {
  if (primary != null) {
    final parts = <String>[
      '${bucket.name} growing ${rate(primary)} (${primary.column.name})',
    ];
    // Name every *other* distinct (bucket, family) growth signal once, by its
    // strongest column — bytes buckets first, then counts.
    final seen = <String>{
      '${bucket.name}:${columnFamily(primary.column).name}',
    };
    for (final a in [...bytesGrowers, ...countGrowers]) {
      if (identical(a, primary)) continue;
      final key =
          '${columnBucket(a.column).name}:${columnFamily(a.column).name}';
      if (seen.add(key)) {
        parts.add(
          'also ${columnBucket(a.column).name} ${rate(a)} (${a.column.name})',
        );
      }
    }
    for (final a in corroborating) {
      parts.add('corroborated by ${a.column.name} (${rate(a)})');
    }
    if (insufficientClause != null) parts.add(insufficientClause);
    return parts.join('; ');
  }

  // No primary-eligible column grew.
  if (corroborating.isNotEmpty) {
    final names = corroborating.map((a) => '${a.column.name} ${rate(a)}');
    final parts = <String>[
      'aggregate growth (${names.join(', ')}) — no deterministic column '
          'isolates a bucket',
    ];
    if (insufficientClause != null) parts.add(insufficientClause);
    return parts.join('; ');
  }

  if (measuredCount == 0) return 'insufficient data: no columns measured';

  // Every measured column assessed as insufficient — say so, rather than
  // implying they were flat.
  if (insufficientCount == measuredCount) return insufficientClause!;

  final parts = <String>['no monotonic growth detected'];
  if (insufficientClause != null) parts.add(insufficientClause);
  return parts.join('; ');
}

String _fmtRate(double value) {
  final magnitude = value.abs();
  if (magnitude >= 100) return value.toStringAsFixed(0);
  if (magnitude >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}
