import 'package:meta/meta.dart';
import 'package:radar_trace/radar_trace.dart';

/// The Lane A signal set — device-agnostic column identifiers for the
/// deterministic `dumpsys`/`/proc` metrics the triage router trends.
///
/// A [TriageTimeline] carries at most one [MetricSeries] per column; a column
/// absent from [TriageTimeline.columns] was never measured (honest by
/// omission — never fabricated as an all-zero series).
enum TriageColumn {
  /// `dumpsys meminfo` App Summary — Java (ART) heap, in KiB.
  javaHeapKb,

  /// `dumpsys meminfo` App Summary — native (jemalloc) PSS, in KiB.
  nativePssKb,

  /// `dumpsys meminfo` App Summary — memtrack Graphics, in KiB.
  graphicsKb,

  /// `dumpsys meminfo` App Summary — Code (mapped .so/.dex/.oat), in KiB.
  codeKb,

  /// `dumpsys meminfo` App Summary — TOTAL PSS, in KiB. Corroborating only.
  totalPssKb,

  /// `/proc/<pid>/status` — RssAnon (anonymous RSS), in KiB.
  rssAnonKb,

  /// `/proc/<pid>/status` — VmRSS (total resident), in KiB. Corroborating.
  vmRssKb,

  /// `/proc/<pid>/status` — Threads, a count.
  threads,

  /// `/proc/<pid>/fd` — total open file descriptors, a count.
  fdTotal,

  /// `/proc/<pid>/fd` — descriptors pointing at `sync_file`, a count.
  fdSyncFile,

  /// `/proc/<pid>/fd` — descriptors pointing at `dmabuf`, a count.
  fdDmabuf,

  /// `/proc/<pid>/fd` — descriptors pointing at `ashmem`/`dev/ashmem`, a count.
  fdAshmem,

  /// `dumpsys gfxinfo` GraphicBufferAllocator total bytes, in KiB.
  gfxBufferKb,

  /// `dumpsys gfxinfo` GraphicBufferAllocator buffer count.
  gfxBufferCount,
}

/// A labeled checkpoint on a [TriageTimeline] — e.g. an app-event marker
/// (`'reconnect'`, `'navigate'`) the router surface aligns trends against.
///
/// Versioned under [TriageTimeline.schemaVersion]; it carries no independent
/// schema field of its own.
@immutable
final class TriageMark {
  /// Host wall-clock microseconds since epoch.
  final int tMicros;

  /// Human label for this checkpoint.
  final String label;

  /// Creates a mark at [tMicros] with [label].
  const TriageMark({required this.tMicros, required this.label});

  /// Restores a mark from [toJson] output.
  factory TriageMark.fromJson(Map<String, Object?> json) => TriageMark(
    tMicros: (json['tMicros'] as num).toInt(),
    label: json['label'] as String,
  );

  /// Serialises this mark to a JSON-encodable map.
  Map<String, Object?> toJson() => {'tMicros': tMicros, 'label': label};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TriageMark && tMicros == other.tMicros && label == other.label;

  @override
  int get hashCode => Object.hash(tMicros, label);

  @override
  String toString() => 'TriageMark($tMicros, $label)';
}

/// Sampled Lane A columns + labeled marks — the input the [triage] router
/// trends per column.
///
/// A column missing from [columns] was never measured; the router assesses
/// only the columns present, so a not-measured column is never silently read
/// as flat.
@immutable
final class TriageTimeline {
  /// The JSON schema version written by [toJson].
  static const int schemaVersion = 1;

  /// One measured series per column. An absent key = never measured.
  final Map<TriageColumn, MetricSeries> columns;

  /// Labeled checkpoints for correlating trends with app events.
  final List<TriageMark> marks;

  /// Creates a timeline over [columns] with optional [marks].
  const TriageTimeline({this.columns = const {}, this.marks = const []});

  /// Restores a timeline from [toJson] output.
  ///
  /// Tolerates absent `columns`/`marks` as empty and an absent
  /// `schemaVersion` (treated as 1). Throws [FormatException] on a newer or
  /// non-numeric schema version, or an unknown [TriageColumn] name — a
  /// corrupt column key must not silently vanish.
  factory TriageTimeline.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != null) {
      if (version is! num) {
        throw FormatException(
          'TriageTimeline schemaVersion must be numeric, got: $version',
        );
      }
      if (version > schemaVersion) {
        throw FormatException(
          'unsupported TriageTimeline schemaVersion $version — '
          'this reader supports <= $schemaVersion',
        );
      }
    }
    final byName = TriageColumn.values.asNameMap();
    final columns = <TriageColumn, MetricSeries>{};
    for (final entry in (json['columns'] as Map? ?? const {}).entries) {
      final name = entry.key as String;
      final column = byName[name];
      if (column == null) {
        throw FormatException('unknown TriageColumn name: $name');
      }
      columns[column] = MetricSeries.fromJson(
        (entry.value as Map).cast<String, Object?>(),
      );
    }
    return TriageTimeline(
      columns: columns,
      marks: [
        for (final m in json['marks'] as List? ?? const [])
          TriageMark.fromJson((m as Map).cast<String, Object?>()),
      ],
    );
  }

  /// Serialises this timeline to a JSON-encodable map carrying
  /// `'schemaVersion': 1`. Columns are keyed by [TriageColumn.name]; absent
  /// columns are simply not present.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'columns': {
      for (final entry in columns.entries) entry.key.name: entry.value.toJson(),
    },
    'marks': [for (final m in marks) m.toJson()],
  };

  @override
  String toString() =>
      'TriageTimeline(${columns.length} columns, ${marks.length} marks)';
}
