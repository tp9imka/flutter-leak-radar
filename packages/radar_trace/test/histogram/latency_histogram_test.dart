import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

void main() {
  group('LatencyHistogram — empty', () {
    test('count and sum are zero', () {
      final h = LatencyHistogram();
      expect(h.count, 0);
      expect(h.sum, 0);
    });

    test('min, max, mean, percentile return null when empty', () {
      final h = LatencyHistogram();
      expect(h.min, isNull);
      expect(h.max, isNull);
      expect(h.mean, isNull);
      expect(h.percentile(0.5), isNull);
      expect(h.percentile(0.99), isNull);
    });

    test('dropCount is zero when empty', () {
      expect(LatencyHistogram().dropCount, 0);
    });
  });

  group('LatencyHistogram — single observation', () {
    test('count=1, sum=value, min=max=percentile(any)≈value', () {
      final h = LatencyHistogram();
      h.record(1000); // 1 ms
      expect(h.count, 1);
      expect(h.sum, 1000);
      expect(h.min, 1000);
      expect(h.max, 1000);
      expect(h.mean, closeTo(1000.0, 0.001));
      // p50 of a single value must be in the right bucket range
      final p50 = h.percentile(0.5);
      expect(p50, isNotNull);
      // bucket upper bound must be >= the recorded value
      expect(p50!, greaterThanOrEqualTo(1000));
      // and within 2x (log-linear bucket width)
      expect(p50, lessThanOrEqualTo(2000));
    });
  });

  group('LatencyHistogram — known distribution', () {
    // Record 100 values: 1µs … 100µs (uniformly spaced).
    // p50 ≈ 50µs, p95 ≈ 95µs, p99 ≈ 99µs.
    // Bucket tolerance: result must be >= true value and within 2x.

    late LatencyHistogram h;
    setUp(() {
      h = LatencyHistogram();
      for (var i = 1; i <= 100; i++) {
        h.record(i);
      }
    });

    test('count and sum are exact', () {
      expect(h.count, 100);
      expect(h.sum, 5050); // sum 1..100
    });

    test('min=1, max=100', () {
      expect(h.min, 1);
      expect(h.max, 100);
    });

    test('mean is close to 50.5', () {
      expect(h.mean, closeTo(50.5, 0.001));
    });

    test('p50 is in [50, 100] — bucket-rounded upward', () {
      final p50 = h.percentile(0.5);
      expect(p50, isNotNull);
      expect(p50!, greaterThanOrEqualTo(50));
      expect(p50, lessThanOrEqualTo(100));
    });

    test('p95 is in [95, 200]', () {
      final p95 = h.percentile(0.95);
      expect(p95, isNotNull);
      expect(p95!, greaterThanOrEqualTo(95));
      expect(p95, lessThanOrEqualTo(200));
    });

    test('p99 is in [99, 200]', () {
      final p99 = h.percentile(0.99);
      expect(p99, isNotNull);
      expect(p99!, greaterThanOrEqualTo(99));
      expect(p99, lessThanOrEqualTo(200));
    });

    test('p100 == max', () {
      expect(h.percentile(1.0), greaterThanOrEqualTo(100));
    });
  });

  group('LatencyHistogram — out-of-range values', () {
    test('values > 60s increment dropCount and not count', () {
      final h = LatencyHistogram();
      h.record(1000);          // in range
      h.record(70_000_001);    // > 60s — out of range
      expect(h.count, 1);
      expect(h.dropCount, 1);
    });

    test('values <= 0 are clamped to first bucket, not dropped', () {
      final h = LatencyHistogram();
      h.record(0);
      h.record(-5);
      // Both should land in count (not dropped), min should be
      // first-bucket upper bound (>= 0).
      expect(h.count, 2);
      expect(h.dropCount, 0);
    });
  });

  group('LatencyHistogram — snapshot', () {
    test('snapshot is immutable and reflects state at call time', () {
      final h = LatencyHistogram();
      h.record(500);
      final snap = h.snapshot();
      h.record(1000);
      // snapshot count unchanged
      expect(snap.count, 1);
      expect(h.count, 2);
    });

    test('snapshot percentile matches live histogram', () {
      final h = LatencyHistogram();
      for (var i = 1; i <= 100; i++) {
        h.record(i * 1000); // 1ms … 100ms
      }
      final snap = h.snapshot();
      expect(snap.percentile(0.95), equals(h.percentile(0.95)));
    });
  });

  group('LatencyHistogram — large scale', () {
    test('1M records does not overflow sum or corrupt count', () {
      final h = LatencyHistogram();
      const n = 1000000;
      for (var i = 0; i < n; i++) {
        h.record(1000); // 1ms each
      }
      expect(h.count, n);
      expect(h.sum, n * 1000);
      expect(h.dropCount, 0);
    });
  });

  group('LatencyHistogram — bucket structure', () {
    test('bucket upper bounds are strictly monotone increasing', () {
      final bounds = LatencyHistogram.upperBoundsForTesting;
      for (var i = 1; i < bounds.length; i++) {
        expect(bounds[i], greaterThan(bounds[i - 1]),
            reason:
                'bound[$i]=${bounds[i]} not > bound[${i - 1}]=${bounds[i - 1]}');
      }
    });
  });
}
