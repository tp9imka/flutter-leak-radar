import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Span _span({
  required String name,
  required int startMicros,
  required int durationMicros,
  String? category,
  SpanStatus status = SpanStatus.ok,
}) {
  final id = SpanId.generate();
  return Span(
    spanId: id,
    parentId: null,
    traceId: id,
    name: name,
    category: category,
    startMicros: startMicros,
    durationMicros: durationMicros,
    status: status,
    attributes: const {},
  );
}

SpanKeyStatsSnapshot _recordAll(List<Span> spans, {int outlierCapacity = 8}) {
  final stats = SpanKeyStats(
    key: TraceKey(name: spans.first.name, category: spans.first.category),
    outlierCapacity: outlierCapacity,
  );
  for (final s in spans) {
    stats.record(s);
  }
  return stats.snapshot();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SpanKeyStatsSnapshot — firstStartMicros / lastStartMicros', () {
    test('single span: first == last == that span startMicros', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 1000, durationMicros: 100),
      ]);
      expect(snap.firstStartMicros, 1000);
      expect(snap.lastStartMicros, 1000);
    });

    test('multiple spans: first is min, last is max of startMicros', () {
      // Record out of order to confirm min/max, not first/last arrival.
      final snap = _recordAll([
        _span(name: 'op', startMicros: 5000, durationMicros: 50),
        _span(name: 'op', startMicros: 1000, durationMicros: 50),
        _span(name: 'op', startMicros: 3000, durationMicros: 50),
      ]);
      expect(snap.firstStartMicros, 1000);
      expect(snap.lastStartMicros, 5000);
    });

    test('values are order-independent: reversed order gives same result', () {
      final spans = [
        _span(name: 'op', startMicros: 9000, durationMicros: 10),
        _span(name: 'op', startMicros: 2000, durationMicros: 10),
        _span(name: 'op', startMicros: 6000, durationMicros: 10),
      ];
      final snap1 = _recordAll(spans);
      final snap2 = _recordAll(spans.reversed.toList());
      expect(snap1.firstStartMicros, snap2.firstStartMicros);
      expect(snap1.lastStartMicros, snap2.lastStartMicros);
    });
  });

  group('SpanKeyStatsSnapshot — avgInterCallIntervalMicros', () {
    test('null when count == 1 (cannot compute interval)', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 1000, durationMicros: 10),
      ]);
      expect(snap.avgInterCallIntervalMicros, isNull);
    });

    test('two spans: interval is exactly lastStart - firstStart', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 1000, durationMicros: 10),
        _span(name: 'op', startMicros: 3000, durationMicros: 10),
      ]);
      // (3000 - 1000) ~/ (2 - 1) = 2000
      expect(snap.avgInterCallIntervalMicros, 2000);
    });

    test('three spans evenly spaced: interval == spacing', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 10),
        _span(name: 'op', startMicros: 1000, durationMicros: 10),
        _span(name: 'op', startMicros: 2000, durationMicros: 10),
      ]);
      // (2000 - 0) ~/ 2 = 1000
      expect(snap.avgInterCallIntervalMicros, 1000);
    });

    test('uses integer truncation (no rounding up)', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 5),
        _span(name: 'op', startMicros: 1000, durationMicros: 5),
        _span(name: 'op', startMicros: 2001, durationMicros: 5),
      ]);
      // (2001 - 0) ~/ 2 = 1000 (truncation)
      expect(snap.avgInterCallIntervalMicros, 1000);
    });
  });

  group('SpanKeyStatsSnapshot — callsPerSecond', () {
    test('null when count == 1', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 10),
      ]);
      expect(snap.callsPerSecond, isNull);
    });

    test('null when window is zero (all startMicros identical)', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 500, durationMicros: 10),
        _span(name: 'op', startMicros: 500, durationMicros: 10),
      ]);
      expect(snap.callsPerSecond, isNull);
    });

    test('two spans 1s apart: rate == 2 calls/s', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 10),
        _span(name: 'op', startMicros: 1_000_000, durationMicros: 10),
      ]);
      // 2 / ((1_000_000 - 0) / 1e6) = 2.0
      expect(snap.callsPerSecond, closeTo(2.0, 1e-9));
    });

    test('four spans over 3s: rate == 4/3 calls/s', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 5),
        _span(name: 'op', startMicros: 1_000_000, durationMicros: 5),
        _span(name: 'op', startMicros: 2_000_000, durationMicros: 5),
        _span(name: 'op', startMicros: 3_000_000, durationMicros: 5),
      ]);
      expect(snap.callsPerSecond, closeTo(4.0 / 3.0, 1e-9));
    });
  });

  group('SpanKeyStatsSnapshot — meanMicros (exact)', () {
    test('single span: mean equals its durationMicros', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 750),
      ]);
      expect(snap.meanMicros, 750);
    });

    test('exact mean via integer truncation of running sum / count', () {
      // sum = 100 + 200 + 303 = 603; count = 3; 603 ~/ 3 = 201
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 100),
        _span(name: 'op', startMicros: 1000, durationMicros: 200),
        _span(name: 'op', startMicros: 2000, durationMicros: 303),
      ]);
      expect(snap.meanMicros, 201);
    });

    test('derived from exact running sum, not bucket approximation', () {
      // Records 1µs each. sum = 100; count = 100. Mean must be exactly 1.
      final spans = List.generate(
        100,
        (i) => _span(name: 'op', startMicros: i * 100, durationMicros: 1),
      );
      final snap = _recordAll(spans);
      expect(snap.meanMicros, 1);
    });
  });

  group('SpanKeyStatsSnapshot — maxMicros (exact)', () {
    test('single span: max equals its durationMicros', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 999),
      ]);
      expect(snap.maxMicros, 999);
    });

    test('max is the slowest span regardless of record order', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 300),
        _span(name: 'op', startMicros: 100, durationMicros: 1500),
        _span(name: 'op', startMicros: 200, durationMicros: 200),
      ]);
      expect(snap.maxMicros, 1500);
    });

    test('exact: not bucket-rounded, even for values like 9µs', () {
      // Bucket for 9µs has upper bound > 9 in the log-linear scheme,
      // but our exact max must still equal 9.
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 9),
        _span(name: 'op', startMicros: 10, durationMicros: 7),
      ]);
      expect(snap.maxMicros, 9);
    });
  });

  group('SpanKeyStatsSnapshot — totalMicros (exact)', () {
    test('total is exact sum of all durationMicros', () {
      final snap = _recordAll([
        _span(name: 'op', startMicros: 0, durationMicros: 100),
        _span(name: 'op', startMicros: 100, durationMicros: 250),
        _span(name: 'op', startMicros: 200, durationMicros: 375),
      ]);
      expect(snap.totalMicros, 725);
    });

    test('matches histogram sum exactly', () {
      final spans = List.generate(
        50,
        (i) => _span(name: 'op', startMicros: i * 200, durationMicros: i + 1),
      );
      final snap = _recordAll(spans);
      // sum(1..50) = 1275
      expect(snap.totalMicros, 1275);
      expect(snap.totalMicros, snap.histogram.sum);
    });
  });

  group('SpanKeyStatsSnapshot — existing fields preserved', () {
    test('count and errorCount still work correctly', () {
      final snap = _recordAll([
        _span(
          name: 'op',
          startMicros: 0,
          durationMicros: 50,
          status: SpanStatus.ok,
        ),
        _span(
          name: 'op',
          startMicros: 100,
          durationMicros: 80,
          status: SpanStatus.error,
        ),
        _span(
          name: 'op',
          startMicros: 200,
          durationMicros: 60,
          status: SpanStatus.error,
        ),
      ]);
      expect(snap.count, 3);
      expect(snap.errorCount, 2);
    });

    test('histogram percentiles still work after adding call metrics', () {
      final spans = List.generate(
        10,
        (i) => _span(
          name: 'op',
          startMicros: i * 1000,
          durationMicros: (i + 1) * 1000,
        ),
      );
      final snap = _recordAll(spans);
      final p50 = snap.histogram.percentile(0.5);
      expect(p50, isNotNull);
      expect(p50!, greaterThan(0));
    });

    test('snapshot is immutable (SpanKeyStatsSnapshot is @immutable)', () {
      // Verify that recording more spans after snapshotting does not mutate
      // the earlier snapshot.
      final stats = SpanKeyStats(
        key: TraceKey(name: 'op', category: null),
        outlierCapacity: 4,
      );
      stats.record(_span(name: 'op', startMicros: 0, durationMicros: 100));
      final snap1 = stats.snapshot();
      stats.record(_span(name: 'op', startMicros: 500, durationMicros: 200));
      final snap2 = stats.snapshot();

      expect(snap1.count, 1);
      expect(snap1.totalMicros, 100);
      expect(snap1.firstStartMicros, 0);
      expect(snap1.lastStartMicros, 0);
      expect(snap1.avgInterCallIntervalMicros, isNull);
      expect(snap2.count, 2);
      expect(snap2.totalMicros, 300);
      expect(snap2.avgInterCallIntervalMicros, 500);
    });
  });

  group('SpanKeyStatsSnapshot — integration via TraceRecorder', () {
    test('recorder propagates call metrics through snapshot', () {
      final rec = TraceRecorder();
      rec.record(_span(name: 'http.get', startMicros: 0, durationMicros: 300));
      rec.record(
        _span(name: 'http.get', startMicros: 2_000_000, durationMicros: 700),
      );
      final key = TraceKey(name: 'http.get', category: null);
      final snap = rec.snapshot().stats[key]!;

      expect(snap.count, 2);
      expect(snap.firstStartMicros, 0);
      expect(snap.lastStartMicros, 2_000_000);
      expect(snap.totalMicros, 1000);
      expect(snap.meanMicros, 500);
      expect(snap.maxMicros, 700);
      // 2 / 2.0s = 1.0 call/s
      expect(snap.callsPerSecond, closeTo(1.0, 1e-9));
      // (2_000_000 - 0) ~/ 1 = 2_000_000
      expect(snap.avgInterCallIntervalMicros, 2_000_000);
    });
  });
}
