import 'package:meta/meta.dart';

/// One row of a heap snapshot: the live-instance count for a single class.
@immutable
final class ClassSample {
  const ClassSample({
    required this.className,
    required this.instancesCurrent,
    required this.bytesCurrent,
    required this.timestamp,
    this.library,
  });

  final String className;
  final String? library;
  final int instancesCurrent;
  final int bytesCurrent;
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      other is ClassSample &&
      other.className == className &&
      other.library == library &&
      other.instancesCurrent == instancesCurrent &&
      other.bytesCurrent == bytesCurrent &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(
    className,
    library,
    instancesCurrent,
    bytesCurrent,
    timestamp,
  );
}

/// A full per-class heap snapshot captured at one instant.
@immutable
final class HeapSnapshot {
  const HeapSnapshot({
    required this.samples,
    required this.capturedAt,
    this.heapBytes,
  });

  final List<ClassSample> samples;
  final DateTime capturedAt;
  final int? heapBytes;
}
