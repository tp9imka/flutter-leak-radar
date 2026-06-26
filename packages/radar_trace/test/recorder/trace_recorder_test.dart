import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

Span _span({
  required String name,
  String? category,
  required int durationMicros,
  SpanStatus status = SpanStatus.ok,
  SpanId? parentId,
  SpanId? traceId,
}) {
  final id = SpanId.generate();
  final tid = traceId ?? id;
  return Span(
    spanId: id,
    parentId: parentId,
    traceId: tid,
    name: name,
    category: category,
    startMicros: 0,
    durationMicros: durationMicros,
    status: status,
    attributes: const {},
  );
}

void main() {
  group('TraceRecorder — disabled', () {
    test('disabled recorder records nothing', () {
      final rec = TraceRecorder(enabled: false);
      rec.record(_span(name: 'op', durationMicros: 500));
      final snap = rec.snapshot();
      expect(snap.stats, isEmpty);
    });
  });

  group('TraceRecorder — basic recording', () {
    test('records a span and creates key stats', () {
      final rec = TraceRecorder();
      rec.record(_span(name: 'db.query', durationMicros: 1000));
      final snap = rec.snapshot();
      expect(snap.stats.length, 1);
      final key = TraceKey(name: 'db.query', category: null);
      expect(snap.stats[key], isNotNull);
      expect(snap.stats[key]!.count, 1);
    });

    test('distinguishes keys by name+category', () {
      final rec = TraceRecorder();
      rec.record(_span(name: 'op', category: 'db', durationMicros: 100));
      rec.record(_span(name: 'op', category: 'http', durationMicros: 200));
      rec.record(_span(name: 'op', durationMicros: 300));
      expect(rec.snapshot().stats.length, 3);
    });

    test('error spans increment errorCount', () {
      final rec = TraceRecorder();
      rec.record(_span(name: 'op', durationMicros: 100, status: SpanStatus.ok));
      rec.record(
        _span(name: 'op', durationMicros: 200, status: SpanStatus.error),
      );
      rec.record(
        _span(name: 'op', durationMicros: 300, status: SpanStatus.error),
      );
      final key = TraceKey(name: 'op', category: null);
      final statsSnap = rec.snapshot().stats[key]!;
      expect(statsSnap.count, 3);
      expect(statsSnap.errorCount, 2);
    });

    test('histogram reflects recorded durations', () {
      final rec = TraceRecorder();
      for (var i = 1; i <= 100; i++) {
        rec.record(_span(name: 'op', durationMicros: i * 1000));
      }
      final key = TraceKey(name: 'op', category: null);
      final hist = rec.snapshot().stats[key]!.histogram;
      expect(hist.count, 100);
      expect(hist.min, 1000);
      expect(hist.max, 100000);
      final p50 = hist.percentile(0.5);
      expect(p50, isNotNull);
      expect(p50!, greaterThanOrEqualTo(50000));
    });

    test('outliers retain the slowest spans', () {
      final rec = TraceRecorder(outlierCapacity: 3);
      rec.record(_span(name: 'op', durationMicros: 100));
      rec.record(_span(name: 'op', durationMicros: 999));
      rec.record(_span(name: 'op', durationMicros: 500));
      rec.record(_span(name: 'op', durationMicros: 50));
      final key = TraceKey(name: 'op', category: null);
      final outliers = rec.snapshot().stats[key]!.outliers;
      final durations = outliers.map((s) => s.durationMicros).toSet();
      expect(durations, containsAll([999, 500, 100]));
      expect(durations.contains(50), isFalse);
    });
  });

  group('TraceRecorder — maxKeys drop counting', () {
    test('spans beyond maxKeys are counted as drops', () {
      final rec = TraceRecorder(maxKeys: 2);
      rec.record(_span(name: 'a', durationMicros: 10));
      rec.record(_span(name: 'b', durationMicros: 10));
      rec.record(_span(name: 'c', durationMicros: 10)); // should drop
      rec.record(_span(name: 'c', durationMicros: 10)); // same key, drop
      expect(rec.keyCount, 2);
      expect(rec.dropCount, 2);
      final snap = rec.snapshot();
      expect(snap.totalDropCount, 2);
    });

    test('existing keys still record after maxKeys reached', () {
      final rec = TraceRecorder(maxKeys: 2);
      rec.record(_span(name: 'a', durationMicros: 10));
      rec.record(_span(name: 'b', durationMicros: 10));
      rec.record(_span(name: 'c', durationMicros: 10)); // dropped
      rec.record(_span(name: 'a', durationMicros: 20)); // existing — OK
      final key = TraceKey(name: 'a', category: null);
      expect(rec.snapshot().stats[key]!.count, 2);
    });
  });

  group('TraceRecorder — reset', () {
    test('reset clears all stats and counters', () {
      final rec = TraceRecorder();
      rec.record(_span(name: 'op', durationMicros: 100));
      rec.reset();
      expect(rec.snapshot().stats, isEmpty);
      expect(rec.keyCount, 0);
      expect(rec.dropCount, 0);
    });
  });

  group('TraceRecorder — snapshot isolation', () {
    test('snapshot is independent of subsequent records', () {
      final rec = TraceRecorder();
      rec.record(_span(name: 'op', durationMicros: 100));
      final snap1 = rec.snapshot();
      rec.record(_span(name: 'op', durationMicros: 200));
      final snap2 = rec.snapshot();
      final key = TraceKey(name: 'op', category: null);
      expect(snap1.stats[key]!.count, 1);
      expect(snap2.stats[key]!.count, 2);
    });
  });
}
