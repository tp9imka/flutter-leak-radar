// lib/src/analysis/sample_history.dart
import 'dart:collection';

import '../engine/class_sample.dart';

/// Bounded ring buffer of recent snapshots with fast per-class series extraction.
class SampleHistory {
  SampleHistory({this.maxSnapshots = 20}) : assert(maxSnapshots >= 2);

  final int maxSnapshots;
  final ListQueue<HeapSnapshot> _snapshots = ListQueue<HeapSnapshot>();

  /// Empties the snapshot ring buffer.
  void clear() => _snapshots.clear();

  void add(HeapSnapshot snapshot) {
    _snapshots.addLast(snapshot);
    while (_snapshots.length > maxSnapshots) {
      _snapshots.removeFirst();
    }
  }

  int get length => _snapshots.length;

  Set<String> get classNames => {
    for (final s in _snapshots)
      for (final sample in s.samples) sample.className,
  };

  /// Live-instance counts oldest→newest; 0 where the class is absent.
  List<int> seriesFor(String className) => [
    for (final s in _snapshots) _countIn(s, className),
  ];

  int latestCountFor(String className) =>
      _snapshots.isEmpty ? 0 : _countIn(_snapshots.last, className);

  /// Total live-object count across all classes in the most recent snapshot,
  /// or null when no snapshot has been captured (e.g. the VM service is not
  /// connected). Lets the engine gate the graph scan on heap size BEFORE
  /// writing a snapshot, avoiding the write+parse OOM on a bloated heap.
  int? get latestObjectTotal => _snapshots.isEmpty
      ? null
      : _snapshots.last.samples.fold<int>(0, (a, s) => a + s.instancesCurrent);

  /// [capturedAt] timestamps oldest→newest, parallel to [seriesFor].
  List<DateTime> get captureTimestamps => [
    for (final s in _snapshots) s.capturedAt,
  ];

  int _countIn(HeapSnapshot s, String className) {
    for (final sample in s.samples) {
      if (sample.className == className) return sample.instancesCurrent;
    }
    return 0;
  }
}
