import 'package:meta/meta.dart';

import 'leak_kind.dart';
import 'retaining_path.dart';

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

  final String className;
  final LeakKind kind;
  final LeakSeverity severity;
  final int liveCount;
  final int growth;
  final String? library;
  final String? tag;
  final List<int> series;
  final RetainingPathView? retainingPath;

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
