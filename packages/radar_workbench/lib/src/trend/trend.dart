import '../capture/snapshot_bundle.dart';

/// One point in a class's trend: its instance/byte count in a single snapshot.
final class TrendPoint {
  const TrendPoint({
    required this.capturedAt,
    required this.instanceCount,
    required this.shallowBytes,
  });
  final DateTime capturedAt;
  final int instanceCount;
  final int shallowBytes;
}

/// A single class's instance/byte counts across N snapshots, oldest first.
final class TrendSeries {
  const TrendSeries({required this.className, required this.points});
  final String className;
  final List<TrendPoint> points;

  int get firstInstances => points.isEmpty ? 0 : points.first.instanceCount;
  int get lastInstances => points.isEmpty ? 0 : points.last.instanceCount;
  int get netInstanceDelta => lastInstances - firstInstances;
}

int _countIn(SnapshotBundle bundle, String className) {
  for (final c in bundle.histogram) {
    if (c.className == className) return c.instanceCount;
  }
  return 0;
}

int _bytesIn(SnapshotBundle bundle, String className) {
  for (final c in bundle.histogram) {
    if (c.className == className) return c.shallowBytes;
  }
  return 0;
}

/// Builds a [TrendSeries] for [className] across [bundles], ordered by
/// [SnapshotBundle.capturedAt]. Snapshots where the class is absent read as 0
/// (matching `computeDiff`'s zero-baseline convention) rather than being
/// dropped, so a class that momentarily vanishes doesn't break the line.
TrendSeries computeTrend(List<SnapshotBundle> bundles, String className) {
  final ordered = [...bundles]
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  return TrendSeries(
    className: className,
    points: [
      for (final b in ordered)
        TrendPoint(
          capturedAt: b.capturedAt,
          instanceCount: _countIn(b, className),
          shallowBytes: _bytesIn(b, className),
        ),
    ],
  );
}

/// Class names whose instance count is strictly higher in the last-captured
/// bundle than in the first — the candidate set for the Trends class picker.
List<String> growingClassNames(List<SnapshotBundle> bundles) {
  if (bundles.length < 2) return const [];
  final ordered = [...bundles]
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  final first = ordered.first;
  final last = ordered.last;
  final names = <String>{
    for (final c in first.histogram) c.className,
    for (final c in last.histogram) c.className,
  };
  final growing =
      <String>[
        for (final name in names)
          if (_countIn(last, name) > _countIn(first, name)) name,
      ]..sort(
        (a, b) => (_countIn(last, b) - _countIn(first, b)).compareTo(
          _countIn(last, a) - _countIn(first, a),
        ),
      );
  return growing;
}
