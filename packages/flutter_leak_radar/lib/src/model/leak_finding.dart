import 'package:meta/meta.dart';

import 'leak_kind.dart';
import 'retaining_path.dart';

/// A single detected memory-leak finding for one class.
///
/// Produced by [LeakReport.findings]. Immutable; identity excludes [series],
/// [captureTimes], and [retainingPath] so UI comparisons stay stable across
/// refresh cycles.
@immutable
final class LeakFinding {
  const LeakFinding({
    required this.className,
    required this.kind,
    required this.severity,
    required this.liveCount,
    required this.growth,
    this.library,
    this.tag,
    this.series = const <int>[],
    this.captureTimes = const <DateTime>[],
    this.retainingPath,
  });

  /// Simple (unqualified) name of the leaking class.
  final String className;

  /// Detection category — growth, notDisposed, notGced, etc.
  final LeakKind kind;

  /// Assessed severity of this finding.
  final LeakSeverity severity;

  /// Current live instance count at scan time.
  final int liveCount;

  /// Net growth in instance count since the first snapshot in the history window.
  final int growth;

  /// Library URI where the class is defined, if available from the VM.
  final String? library;

  /// Optional caller-supplied label from [LeakRadar.track].
  final String? tag;

  /// Rolling history of live-count samples used for sparkline rendering.
  final List<int> series;

  /// Timestamps of each capture in [series], oldest→newest.
  final List<DateTime> captureTimes;

  /// Retaining path fetched on demand; null until the user expands the tile.
  final RetainingPathView? retainingPath;

  /// The [DateTime] of the first capture where this class had count > 0.
  DateTime? get firstSeen {
    for (var i = 0; i < series.length; i++) {
      if (series[i] > 0 && i < captureTimes.length) {
        return captureTimes[i];
      }
    }
    return null;
  }

  /// Returns a copy of this finding with [retainingPath] set.
  LeakFinding withRetainingPath(RetainingPathView path) => LeakFinding(
    className: className,
    kind: kind,
    severity: severity,
    liveCount: liveCount,
    growth: growth,
    library: library,
    tag: tag,
    series: series,
    captureTimes: captureTimes,
    retainingPath: path,
  );

  Map<String, Object?> toJson() => {
    'className': className,
    'kind': kind.name,
    'severity': severity.name,
    'liveCount': liveCount,
    'growth': growth,
    if (library != null) 'library': library,
    if (tag != null) 'tag': tag,
    'series': series,
    'captureTimes': captureTimes.map((dt) => dt.toIso8601String()).toList(),
    if (retainingPath != null) 'retainingPath': retainingPath!.toJson(),
  };

  static LeakFinding fromJson(Map<String, Object?> json) => LeakFinding(
    className: json['className'] as String,
    kind: LeakKind.values.byName(json['kind'] as String),
    severity: LeakSeverity.values.byName(json['severity'] as String),
    liveCount: json['liveCount'] as int,
    growth: json['growth'] as int,
    library: json['library'] as String?,
    tag: json['tag'] as String?,
    series:
        (json['series'] as List<Object?>?)?.map((e) => e as int).toList() ??
        const <int>[],
    captureTimes:
        (json['captureTimes'] as List<Object?>?)
            ?.map((e) => DateTime.parse(e as String))
            .toList() ??
        const <DateTime>[],
    retainingPath: json['retainingPath'] != null
        ? _retainingPathFromJson(json['retainingPath'] as Map<String, Object?>)
        : null,
  );

  // series, captureTimes, and retainingPath are intentionally excluded from
  // identity
  @override
  bool operator ==(Object other) =>
      other is LeakFinding &&
      other.className == className &&
      other.kind == kind &&
      other.severity == severity &&
      other.liveCount == liveCount &&
      other.growth == growth &&
      other.library == library &&
      other.tag == tag;

  @override
  int get hashCode =>
      Object.hash(className, kind, severity, liveCount, growth, library, tag);
}

RetainingPathView _retainingPathFromJson(Map<String, Object?> json) =>
    RetainingPathView(
      gcRootType: json['gcRootType'] as String?,
      elements: (json['elements'] as List<Object?>)
          .map((e) => _retainingHopFromJson(e as Map<String, Object?>))
          .toList(),
    );

RetainingHop _retainingHopFromJson(Map<String, Object?> json) => RetainingHop(
  objectType: json['objectType'] as String,
  field: json['field'] as String?,
  index: json['index'] as int?,
  mapKey: json['mapKey'] as String?,
);
