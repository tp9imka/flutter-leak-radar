import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

Span _makeSpan(int durationMicros) => Span(
  spanId: SpanId.generate(),
  parentId: null,
  traceId: SpanId.generate(),
  name: 'op',
  category: null,
  startMicros: 0,
  durationMicros: durationMicros,
  status: SpanStatus.ok,
  attributes: const {},
);

void main() {
  group('OutlierRing — basic retention', () {
    test('empty ring has count 0 and empty spans list', () {
      final ring = OutlierRing(capacity: 4);
      expect(ring.count, 0);
      expect(ring.spans, isEmpty);
      expect(ring.offeredCount, 0);
    });

    test('below-capacity offers are all retained', () {
      final ring = OutlierRing(capacity: 4);
      ring.offer(_makeSpan(100));
      ring.offer(_makeSpan(200));
      ring.offer(_makeSpan(300));
      expect(ring.count, 3);
      expect(ring.offeredCount, 3);
      final durations = ring.spans.map((s) => s.durationMicros).toList();
      expect(durations, containsAll([100, 200, 300]));
    });

    test('spans are returned slowest-first', () {
      final ring = OutlierRing(capacity: 4);
      ring.offer(_makeSpan(300));
      ring.offer(_makeSpan(100));
      ring.offer(_makeSpan(200));
      final durations = ring.spans.map((s) => s.durationMicros).toList();
      expect(durations, [300, 200, 100]);
    });
  });

  group('OutlierRing — eviction at capacity', () {
    test('evicts smallest when new span is slower', () {
      final ring = OutlierRing(capacity: 3);
      ring.offer(_makeSpan(100));
      ring.offer(_makeSpan(200));
      ring.offer(_makeSpan(300));
      // Ring is full; 50µs is slower than nothing but SLOWER is >=
      // min(100). 50 < 100 so it should NOT enter.
      ring.offer(_makeSpan(50));
      expect(ring.count, 3);
      final durations = ring.spans.map((s) => s.durationMicros).toSet();
      expect(durations, {100, 200, 300});
      expect(ring.offeredCount, 4);
    });

    test('evicts smallest when new span is the new slowest', () {
      final ring = OutlierRing(capacity: 3);
      ring.offer(_makeSpan(100));
      ring.offer(_makeSpan(200));
      ring.offer(_makeSpan(300));
      ring.offer(_makeSpan(999));
      expect(ring.count, 3);
      final durations = ring.spans.map((s) => s.durationMicros).toSet();
      expect(durations, {200, 300, 999});
      expect(durations.contains(100), isFalse);
    });
  });

  group('OutlierRing — offeredCount accounting', () {
    test('offeredCount tracks all offers regardless of eviction', () {
      final ring = OutlierRing(capacity: 2);
      for (var i = 0; i < 10; i++) {
        ring.offer(_makeSpan(i * 100));
      }
      expect(ring.offeredCount, 10);
      expect(ring.count, 2);
    });
  });

  group('OutlierRing — spans snapshot is independent', () {
    test('modifying returned list does not affect ring', () {
      final ring = OutlierRing(capacity: 4);
      ring.offer(_makeSpan(100));
      final snapshot = ring.spans;
      snapshot.clear();
      expect(ring.count, 1);
    });
  });
}
