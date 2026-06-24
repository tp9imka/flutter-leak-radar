// test/analysis/sample_history_test.dart
import 'package:flutter_leak_radar/src/analysis/sample_history.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_test/flutter_test.dart';

HeapSnapshot snap(Map<String, int> counts, int t) => HeapSnapshot(
  capturedAt: DateTime(2026, 1, 1, 0, 0, t),
  samples: [
    for (final e in counts.entries)
      ClassSample(
        className: e.key,
        instancesCurrent: e.value,
        bytesCurrent: e.value * 8,
        timestamp: DateTime(2026, 1, 1, 0, 0, t),
      ),
  ],
);

void main() {
  test('bounds to maxSnapshots, dropping oldest', () {
    final h = SampleHistory(maxSnapshots: 2);
    h
      ..add(snap({'A': 1}, 1))
      ..add(snap({'A': 2}, 2))
      ..add(snap({'A': 3}, 3));
    expect(h.length, 2);
    expect(h.seriesFor('A'), [2, 3]);
  });

  test('seriesFor pads absent classes with 0', () {
    final h = SampleHistory(maxSnapshots: 5);
    h
      ..add(snap({'A': 1}, 1))
      ..add(snap({'B': 9}, 2));
    expect(h.seriesFor('A'), [1, 0]);
    expect(h.seriesFor('B'), [0, 9]);
  });

  test('latestCountFor reads the newest snapshot', () {
    final h = SampleHistory(maxSnapshots: 5);
    h
      ..add(snap({'A': 1}, 1))
      ..add(snap({'A': 4}, 2));
    expect(h.latestCountFor('A'), 4);
    expect(h.latestCountFor('Z'), 0);
  });
}
