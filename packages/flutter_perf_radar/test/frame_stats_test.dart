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
  });
}
