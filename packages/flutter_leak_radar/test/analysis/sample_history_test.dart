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

  test('latestObjectTotal sums the newest snapshot across classes', () {
    final h = SampleHistory(maxSnapshots: 5);
    h
      ..add(snap({'A': 1, 'B': 2}, 1))
      ..add(snap({'A': 10, 'B': 20, 'C': 5}, 2));
    expect(h.latestObjectTotal, 35);
  });

  test('latestObjectTotal is null when no snapshot captured', () {
    expect(SampleHistory().latestObjectTotal, isNull);
  });

  test(
    'latestBytesFor reads bytesCurrent from the newest bearing snapshot',
    () {
      final h = SampleHistory(maxSnapshots: 5)
        ..add(snap({'A': 1}, 1)) // bytesCurrent 8
        ..add(snap({'A': 10}, 2)); // bytesCurrent 80
      expect(h.latestBytesFor('A'), 80);
    },
  );

  test('latestBytesFor is null for an unknown class', () {
    final h = SampleHistory()..add(snap({'A': 1}, 1));
    expect(h.latestBytesFor('Z'), isNull);
  });

  test('latestBytesFor treats 0 bytes as unmeasured (null)', () {
    final t0 = DateTime(2026);
    final h = SampleHistory()
      ..add(
        HeapSnapshot(
          capturedAt: t0,
          samples: [
            ClassSample(
              className: 'A',
              instancesCurrent: 3,
              bytesCurrent: 0,
              timestamp: t0,
            ),
          ],
        ),
      );
    expect(h.latestBytesFor('A'), isNull);
  });

  test('latestHeapBytes returns the newest snapshot heapBytes', () {
    final h = SampleHistory()
      ..add(HeapSnapshot(capturedAt: DateTime(2026), samples: const []))
      ..add(
        HeapSnapshot(
          capturedAt: DateTime(2026, 1, 2),
          samples: const [],
          heapBytes: 4096,
        ),
      );
    expect(h.latestHeapBytes, 4096);
  });

  test('latestHeapBytes is null when unmeasured or empty', () {
    expect(SampleHistory().latestHeapBytes, isNull);
    final h = SampleHistory()
      ..add(HeapSnapshot(capturedAt: DateTime(2026), samples: const []));
    expect(h.latestHeapBytes, isNull);
  });

  test('libraryUris yields parseable URIs and drops null libraries', () {
    final t0 = DateTime(2026);
    final h = SampleHistory()
      ..add(
        HeapSnapshot(
          capturedAt: t0,
          samples: [
            ClassSample(
              className: 'A',
              instancesCurrent: 1,
              bytesCurrent: 8,
              library: 'package:my_app/a.dart',
              timestamp: t0,
            ),
            ClassSample(
              className: 'B',
              instancesCurrent: 1,
              bytesCurrent: 8,
              library: 'dart:async',
              timestamp: t0,
            ),
            ClassSample(
              className: 'C',
              instancesCurrent: 1,
              bytesCurrent: 8,
              timestamp: t0,
            ),
            ClassSample(
              className: 'D',
              instancesCurrent: 1,
              bytesCurrent: 8,
              library: 'package:my_app/b.dart',
              timestamp: t0,
            ),
          ],
        ),
      );
    final strings = h.libraryUris().map((u) => u.toString()).toList();
    // Null libraries are dropped; parseable URIs (incl. dart:) are yielded.
    // Filtering to package: happens in AppPackageSet.autoDetect.
    expect(strings, contains('package:my_app/a.dart'));
    expect(strings, contains('package:my_app/b.dart'));
    expect(strings.length, 3);
  });
}
