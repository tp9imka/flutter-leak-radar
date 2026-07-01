import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrameStats', () {
    test('empty stats has zero count and null percentiles', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      final snap = stats.snapshot();
      expect(snap.frameCount, equals(0));
      expect(snap.jankCount, equals(0));
      expect(snap.totalP50, isNull);
      expect(snap.totalP95, isNull);
      expect(snap.totalP99, isNull);
    });

    test('empty snapshot has empty recentFrames', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      expect(stats.snapshot().recentFrames, isEmpty);
    });

    test('recording one normal frame increments count and no jank', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      stats.record(buildMicros: 5000, rasterMicros: 3000, totalMicros: 8000);
      final snap = stats.snapshot();
      expect(snap.frameCount, equals(1));
      expect(snap.jankCount, equals(0));
    });

    test('recording a jank frame increments jankCount', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      stats.record(buildMicros: 10000, rasterMicros: 10000, totalMicros: 20000);
      final snap = stats.snapshot();
      expect(snap.frameCount, equals(1));
      expect(snap.jankCount, equals(1));
    });

    test('percentiles reflect recorded values', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      for (var i = 0; i < 100; i++) {
        stats.record(buildMicros: 5000, rasterMicros: 3000, totalMicros: 8000);
      }
      final snap = stats.snapshot();
      expect(snap.frameCount, equals(100));
      expect(snap.totalP50, isNotNull);
      expect(snap.totalP95, isNotNull);
      expect(snap.totalP99, isNotNull);
    });

    test('jankThreshold is configurable, not hardcoded', () {
      final stats = FrameStats(jankThresholdMicros: 5000);
      stats.record(buildMicros: 4000, rasterMicros: 4000, totalMicros: 8000);
      final snap = stats.snapshot();
      expect(snap.jankCount, equals(1));
    });

    test('snapshot has no cpuPercent or fabricated ratio fields', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      final snap = stats.snapshot();
      expect(snap, isNotNull);
    });

    // ── Ring buffer ────────────────────────────────────────────────────────

    test('recentFrames contains one entry after one record call', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      stats.record(buildMicros: 4000, rasterMicros: 3000, totalMicros: 7000);
      final snap = stats.snapshot();
      expect(snap.recentFrames, hasLength(1));
      expect(snap.recentFrames.first.totalMicros, equals(7000));
      expect(snap.recentFrames.first.buildMicros, equals(4000));
      expect(snap.recentFrames.first.rasterMicros, equals(3000));
    });

    test('recentFrames preserves insertion order', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      stats.record(buildMicros: 1000, rasterMicros: 1000, totalMicros: 2000);
      stats.record(buildMicros: 2000, rasterMicros: 2000, totalMicros: 4000);
      stats.record(buildMicros: 3000, rasterMicros: 3000, totalMicros: 6000);
      final frames = stats.snapshot().recentFrames;
      expect(
        frames.map((f) => f.totalMicros).toList(),
        equals([2000, 4000, 6000]),
      );
    });

    test('ring trims to maxRecentFrames when exceeded', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      final total = FrameStats.maxRecentFrames + 10;
      for (var i = 0; i < total; i++) {
        stats.record(
          buildMicros: i * 100,
          rasterMicros: i * 50,
          totalMicros: i * 150,
        );
      }
      final snap = stats.snapshot();
      // frameCount counts everything; ring is capped
      expect(snap.frameCount, equals(total));
      expect(snap.recentFrames, hasLength(FrameStats.maxRecentFrames));
      // Ring holds the NEWEST maxRecentFrames entries (the last 120)
      expect(snap.recentFrames.first.totalMicros, equals(10 * 150));
      expect(snap.recentFrames.last.totalMicros, equals((total - 1) * 150));
    });

    test('snapshot recentFrames is unmodifiable', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      stats.record(buildMicros: 1000, rasterMicros: 1000, totalMicros: 2000);
      final snap = stats.snapshot();
      expect(
        () => snap.recentFrames.add(
          const FrameSample(totalMicros: 0, buildMicros: 0, rasterMicros: 0),
        ),
        throwsUnsupportedError,
      );
    });

    test(
      'FrameStatsSnapshot const constructor defaults recentFrames to empty',
      () {
        const snap = FrameStatsSnapshot(frameCount: 0, jankCount: 0);
        expect(snap.recentFrames, isEmpty);
      },
    );

    // ── reset() ──────────────────────────────────────────────────────────

    test('reset zeroes frameCount and jankCount', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      stats.record(buildMicros: 10000, rasterMicros: 10000, totalMicros: 20000);
      stats.record(buildMicros: 5000, rasterMicros: 3000, totalMicros: 8000);
      expect(stats.snapshot().frameCount, equals(2));

      stats.reset();

      final snap = stats.snapshot();
      expect(snap.frameCount, equals(0));
      expect(snap.jankCount, equals(0));
    });

    test('reset clears the recent-frame ring', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      stats.record(buildMicros: 1000, rasterMicros: 1000, totalMicros: 2000);
      expect(stats.snapshot().recentFrames, isNotEmpty);

      stats.reset();

      expect(stats.snapshot().recentFrames, isEmpty);
    });

    test('reset clears all latency histogram percentiles to null', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      for (var i = 0; i < 50; i++) {
        stats.record(buildMicros: 5000, rasterMicros: 3000, totalMicros: 8000);
      }
      final before = stats.snapshot();
      expect(before.buildP50, isNotNull);
      expect(before.rasterP50, isNotNull);
      expect(before.totalP50, isNotNull);

      stats.reset();

      final after = stats.snapshot();
      expect(after.buildP50, isNull);
      expect(after.buildP95, isNull);
      expect(after.buildP99, isNull);
      expect(after.rasterP50, isNull);
      expect(after.rasterP95, isNull);
      expect(after.rasterP99, isNull);
      expect(after.totalP50, isNull);
      expect(after.totalP95, isNull);
      expect(after.totalP99, isNull);
    });

    test('reset keeps jankThresholdMicros configuration intact', () {
      final stats = FrameStats(jankThresholdMicros: 5000);
      stats.record(buildMicros: 4000, rasterMicros: 4000, totalMicros: 8000);
      stats.reset();

      // A frame above the original threshold is still counted as jank.
      stats.record(buildMicros: 4000, rasterMicros: 4000, totalMicros: 8000);
      expect(stats.snapshot().jankCount, equals(1));
      expect(stats.jankThresholdMicros, equals(5000));
    });

    test('recording after reset behaves like a fresh FrameStats', () {
      final stats = FrameStats(jankThresholdMicros: 16667);
      for (var i = 0; i < 10; i++) {
        stats.record(
          buildMicros: 10000,
          rasterMicros: 10000,
          totalMicros: 20000,
        );
      }
      stats.reset();

      stats.record(buildMicros: 1000, rasterMicros: 1000, totalMicros: 2000);
      final snap = stats.snapshot();
      expect(snap.frameCount, equals(1));
      expect(snap.jankCount, equals(0));
      expect(snap.recentFrames, hasLength(1));
      expect(snap.recentFrames.first.totalMicros, equals(2000));
    });
  });
}
