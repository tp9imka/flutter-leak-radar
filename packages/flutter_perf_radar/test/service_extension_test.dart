import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // FrameStatsSnapshot.toJson
  // ---------------------------------------------------------------------------
  group('FrameStatsSnapshot.toJson', () {
    test('empty snapshot has correct shape with null percentiles', () {
      const snap = FrameStatsSnapshot(frameCount: 0, jankCount: 0);
      final json = snap.toJson();

      expect(json['frameCount'], equals(0));
      expect(json['jankCount'], equals(0));
      expect(json['buildP50'], isNull);
      expect(json['buildP95'], isNull);
      expect(json['buildP99'], isNull);
      expect(json['rasterP50'], isNull);
      expect(json['rasterP95'], isNull);
      expect(json['rasterP99'], isNull);
      expect(json['totalP50'], isNull);
      expect(json['totalP95'], isNull);
      expect(json['totalP99'], isNull);
      expect(json['recentFrames'], isEmpty);
    });

    test('recentFrames is serialised with all three timing fields', () {
      const snap = FrameStatsSnapshot(
        frameCount: 2,
        jankCount: 0,
        recentFrames: [
          FrameSample(totalMicros: 16000, buildMicros: 800, rasterMicros: 900),
          FrameSample(totalMicros: 17000, buildMicros: 900, rasterMicros: 1000),
        ],
      );
      final json = snap.toJson();
      final frames = json['recentFrames'] as List;

      expect(frames, hasLength(2));
      final first = frames[0] as Map;
      expect(first['totalMicros'], equals(16000));
      expect(first['buildMicros'], equals(800));
      expect(first['rasterMicros'], equals(900));
    });

    test('non-null percentiles are forwarded exactly', () {
      const snap = FrameStatsSnapshot(
        frameCount: 10,
        jankCount: 1,
        buildP50: 800,
        buildP95: 3000,
        buildP99: 6000,
        rasterP50: 900,
        rasterP95: 3200,
        rasterP99: 6500,
        totalP50: 1800,
        totalP95: 6000,
        totalP99: 12000,
      );
      final json = snap.toJson();

      expect(json['buildP50'], equals(800));
      expect(json['buildP95'], equals(3000));
      expect(json['buildP99'], equals(6000));
      expect(json['rasterP50'], equals(900));
      expect(json['rasterP95'], equals(3200));
      expect(json['rasterP99'], equals(6500));
      expect(json['totalP50'], equals(1800));
      expect(json['totalP95'], equals(6000));
      expect(json['totalP99'], equals(12000));
      expect(json['jankCount'], equals(1));
    });

    test('recentFrames order is chronological (insertion order preserved)', () {
      const snap = FrameStatsSnapshot(
        frameCount: 3,
        jankCount: 0,
        recentFrames: [
          FrameSample(totalMicros: 1000, buildMicros: 100, rasterMicros: 200),
          FrameSample(totalMicros: 2000, buildMicros: 200, rasterMicros: 300),
          FrameSample(totalMicros: 3000, buildMicros: 300, rasterMicros: 400),
        ],
      );
      final frames = snap.toJson()['recentFrames'] as List;

      expect((frames[0] as Map)['totalMicros'], equals(1000));
      expect((frames[1] as Map)['totalMicros'], equals(2000));
      expect((frames[2] as Map)['totalMicros'], equals(3000));
    });
  });

  // ---------------------------------------------------------------------------
  // StabilitySnapshot.toJson
  // ---------------------------------------------------------------------------
  group('StabilitySnapshot.toJson', () {
    test('empty snapshot has correct shape', () {
      const snap = StabilitySnapshot(
        errorCount: 0,
        stallCount: 0,
        recentErrors: [],
        recentStalls: [],
      );
      final json = snap.toJson();

      expect(json['errorCount'], equals(0));
      expect(json['stallCount'], equals(0));
      expect(json['recentErrors'], isEmpty);
      expect(json['recentStalls'], isEmpty);
    });

    test('recentErrors serialises all ErrorRecord fields', () {
      const snap = StabilitySnapshot(
        errorCount: 1,
        stallCount: 0,
        recentErrors: [
          ErrorRecord(
            message: 'Connection refused',
            clockMicros: 123456789,
            context: 'FlutterError',
            stackTraceString: '#0 main (file:///app/main.dart:10)',
          ),
        ],
        recentStalls: [],
      );
      final json = snap.toJson();
      final errors = json['recentErrors'] as List;

      expect(errors, hasLength(1));
      final e = errors[0] as Map;
      expect(e['message'], equals('Connection refused'));
      expect(e['context'], equals('FlutterError'));
      expect(e['clockMicros'], equals(123456789));
      expect(
        e['stackTraceString'],
        equals('#0 main (file:///app/main.dart:10)'),
      );
    });

    test('null context and stackTraceString are serialised as null', () {
      const snap = StabilitySnapshot(
        errorCount: 1,
        stallCount: 0,
        recentErrors: [ErrorRecord(message: 'boom', clockMicros: 1000)],
        recentStalls: [],
      );
      final errors = snap.toJson()['recentErrors'] as List;
      final e = errors[0] as Map;

      expect(e['context'], isNull);
      expect(e['stackTraceString'], isNull);
    });

    test('recentStalls serialises durationMicros and clockMicros', () {
      const snap = StabilitySnapshot(
        errorCount: 0,
        stallCount: 2,
        recentErrors: [],
        recentStalls: [
          StallRecord(durationMicros: 320000, clockMicros: 987654321),
          StallRecord(durationMicros: 450000, clockMicros: 999999999),
        ],
      );
      final stalls = snap.toJson()['recentStalls'] as List;

      expect(stalls, hasLength(2));
      expect((stalls[0] as Map)['durationMicros'], equals(320000));
      expect((stalls[0] as Map)['clockMicros'], equals(987654321));
      expect((stalls[1] as Map)['durationMicros'], equals(450000));
    });

    test('no fabricated fields — only real ErrorRecord/StallRecord fields', () {
      const snap = StabilitySnapshot(
        errorCount: 1,
        stallCount: 1,
        recentErrors: [
          ErrorRecord(
            message: 'err',
            clockMicros: 1,
            context: 'ctx',
            stackTraceString: 'st',
          ),
        ],
        recentStalls: [StallRecord(durationMicros: 1000, clockMicros: 2000)],
      );
      final json = snap.toJson();
      final errorKeys =
          (json['recentErrors'] as List).first.keys.toSet() as Set;
      final stallKeys =
          (json['recentStalls'] as List).first.keys.toSet() as Set;

      // Only the four real ErrorRecord fields.
      expect(
        errorKeys,
        equals({'message', 'context', 'clockMicros', 'stackTraceString'}),
      );
      // Only the two real StallRecord fields.
      expect(stallKeys, equals({'durationMicros', 'clockMicros'}));
    });
  });

  // ---------------------------------------------------------------------------
  // perfRadarSnapshotJson assembles all three sections
  // ---------------------------------------------------------------------------
  group('perfRadarSnapshotJson', () {
    test('returns a map with traces, frames, and stability keys', () {
      final json = perfRadarSnapshotJson();

      expect(json, containsPair('traces', isA<Map>()));
      expect(json, containsPair('frames', isA<Map>()));
      expect(json, containsPair('stability', isA<Map>()));
    });

    test('traces section has totalDropCount and keys list', () {
      final traces = perfRadarSnapshotJson()['traces'] as Map;

      expect(traces, contains('totalDropCount'));
      expect(traces['keys'], isA<List>());
    });

    test('frames section has frameCount and recentFrames', () {
      final frames = perfRadarSnapshotJson()['frames'] as Map;

      expect(frames, contains('frameCount'));
      expect(frames, contains('jankCount'));
      expect(frames['recentFrames'], isA<List>());
    });

    test('stability section has errorCount, stallCount, and lists', () {
      final stability = perfRadarSnapshotJson()['stability'] as Map;

      expect(stability, contains('errorCount'));
      expect(stability, contains('stallCount'));
      expect(stability['recentErrors'], isA<List>());
      expect(stability['recentStalls'], isA<List>());
    });

    test('function is pure — called twice returns consistent structure', () {
      final a = perfRadarSnapshotJson();
      final b = perfRadarSnapshotJson();

      // Both calls should produce the same top-level keys.
      expect(a.keys.toSet(), equals(b.keys.toSet()));
    });
  });
}
