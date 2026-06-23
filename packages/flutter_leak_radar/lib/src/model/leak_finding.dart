import 'package:meta/meta.dart';

import 'leak_kind.dart';
import 'retaining_path.dart';

/// A single detected memory-leak finding for one class.
///
/// Produced by [LeakReport.findings]. Immutable; identity excludes [series]
/// and [retainingPath] so UI comparisons stay stable across refresh cycles.
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

  /// Retaining path fetched on demand; null until the user expands the tile.
  final RetainingPathView? retainingPath;

  /// Returns a copy of this finding with [retainingPath] set.
  LeakFinding withRetainingPath(RetainingPathView path) => LeakFinding(
        className: className, kind: kind, severity: severity, liveCount: liveCount,
        growth: growth, library: library, tag: tag, series: series, retainingPath: path,
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
        if (retainingPath != null) 'retainingPath': retainingPath!.toJson(),
      };

  // series and retainingPath are intentionally excluded from identity
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
  int get hashCode => Object.hash(className, kind, severity, liveCount, growth, library, tag);
}
