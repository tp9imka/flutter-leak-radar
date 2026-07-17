import 'dart:convert';

import 'package:radar_ci/radar_ci.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';

void main() {
  group('RadarRunDocument round-trip', () {
    RadarRunDocument sample() => RadarRunDocument(
      metadata: RunMetadata(
        startedAt: DateTime.utc(2026, 7, 17, 9, 30, 15),
        flutterVersion: '3.44.4',
        dartVersion: '3.12.0',
        targetPlatform: 'android-arm64',
        mode: 'profile',
        cmdLine: 'flutter run --profile -d emulator',
        notes: 'nightly',
        projectPackages: const ['katim_connect', 'katim_core'],
        projectPackagesSource: 'flag',
      ),
      series: [
        const MetricSeries(
          name: 'dart.heap.used',
          unit: 'bytes',
          samples: [
            MetricSample(tMicros: 1000, value: 2048),
            MetricSample(tMicros: 6000, value: 4096),
          ],
          gaps: [
            SeriesGap(
              startMicros: 6000,
              endMicros: 11000,
              reason: 'sampler error: boom',
            ),
          ],
        ),
      ],
      checkpoints: const [
        RunCheckpoint(
          tMicros: 0,
          label: 'start',
          allocationTopN: {'String': 120, 'List': 44},
          snapshotPath: 'snap_start.data',
          analysisPath: 'snap_start.analysis.json',
        ),
        RunCheckpoint(
          tMicros: 90000000,
          label: 'cp1',
          allocationTopN: {},
          captureStatus: 'failed',
          captureError: 'allocation profile failed: socket closed',
        ),
        RunCheckpoint(tMicros: 180000000, label: 'end', allocationTopN: {}),
      ],
    );

    test('preserves every field through toJson/fromJson', () {
      final original = sample();
      final restored = RadarRunDocument.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );

      expect(restored.schemaVersion, 1);
      expect(restored.metadata.startedAt, original.metadata.startedAt);
      expect(restored.metadata.flutterVersion, '3.44.4');
      expect(restored.metadata.dartVersion, '3.12.0');
      expect(restored.metadata.targetPlatform, 'android-arm64');
      expect(restored.metadata.mode, 'profile');
      expect(restored.metadata.cmdLine, original.metadata.cmdLine);
      expect(restored.metadata.notes, 'nightly');
      expect(restored.metadata.projectPackages, [
        'katim_connect',
        'katim_core',
      ]);
      expect(restored.metadata.projectPackagesSource, 'flag');

      expect(restored.series, hasLength(1));
      expect(restored.series.single.name, 'dart.heap.used');
      expect(restored.series.single.samples, hasLength(2));
      expect(restored.series.single.gaps.single.reason, 'sampler error: boom');

      expect(restored.checkpoints, hasLength(3));
      expect(restored.checkpoints.first.label, 'start');
      expect(restored.checkpoints.first.allocationTopN['String'], 120);
      expect(restored.checkpoints.first.snapshotPath, 'snap_start.data');
      expect(
        restored.checkpoints.first.analysisPath,
        'snap_start.analysis.json',
      );
      expect(restored.checkpoints.first.captureStatus, 'ok');
      expect(restored.checkpoints.first.captureError, isNull);
      expect(restored.checkpoints[1].captureStatus, 'failed');
      expect(
        restored.checkpoints[1].captureError,
        'allocation profile failed: socket closed',
      );
      expect(restored.checkpoints.last.snapshotPath, isNull);

      expect(restored.metadata.completed, isTrue);
      expect(restored.metadata.abortReason, isNull);
    });

    test('round-trips a partial, aborted run', () {
      final aborted = RadarRunDocument(
        metadata: RunMetadata(
          startedAt: DateTime.utc(2026),
          completed: false,
          abortReason: 'interrupted',
        ),
        series: const [],
        checkpoints: const [],
      );
      final restored = RadarRunDocument.fromJson(
        jsonDecode(jsonEncode(aborted.toJson())) as Map<String, Object?>,
      );
      expect(restored.metadata.completed, isFalse);
      expect(restored.metadata.abortReason, 'interrupted');
    });

    test('legacy docs without the new fields default to complete/ok', () {
      final restored = RadarRunDocument.fromJson({
        'metadata': {'startedAt': '2026-07-17T09:30:15.000Z'},
        'checkpoints': [
          {'tMicros': 0, 'label': 'start', 'allocationTopN': <String, int>{}},
        ],
      });
      expect(restored.metadata.completed, isTrue);
      expect(restored.checkpoints.single.captureStatus, 'ok');
    });

    test('stamps schemaVersion 1 in JSON', () {
      expect(sample().toJson()['schemaVersion'], 1);
    });

    test('tolerates absent optional metadata and empty collections', () {
      final restored = RadarRunDocument.fromJson({
        'metadata': {'startedAt': '2026-07-17T09:30:15.000Z'},
      });
      expect(restored.metadata.flutterVersion, isNull);
      expect(restored.metadata.projectPackages, isEmpty);
      expect(restored.series, isEmpty);
      expect(restored.checkpoints, isEmpty);
    });

    test('treats absent schemaVersion as legacy v1 (tolerant)', () {
      final restored = RadarRunDocument.fromJson({
        'metadata': {'startedAt': '2026-07-17T09:30:15.000Z'},
        'series': const [],
        'checkpoints': const [],
      });
      expect(restored.schemaVersion, 1);
    });

    test('refuses a newer major schemaVersion as a tool failure', () {
      expect(
        () => RadarRunDocument.fromJson({
          'schemaVersion': 2,
          'metadata': {'startedAt': '2026-07-17T09:30:15.000Z'},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RadarRunDocument.nativeTimeline (additive Lane A field)', () {
    TriageTimeline nativeTimeline() => TriageTimeline(
      columns: {
        TriageColumn.nativePssKb: const MetricSeries(
          name: 'nativePssKb',
          unit: 'kb',
          samples: [
            MetricSample(tMicros: 1000, value: 100),
            MetricSample(tMicros: 11000, value: 140),
          ],
          gaps: [
            SeriesGap(
              startMicros: 11000,
              endMicros: 21000,
              reason: 'process not running',
            ),
          ],
        ),
        TriageColumn.threads: const MetricSeries(
          name: 'threads',
          unit: 'count',
          samples: [MetricSample(tMicros: 1000, value: 24)],
        ),
      },
      marks: const [TriageMark(tMicros: 1000, label: 'start')],
    );

    test('round-trips a co-driven native timeline (columns + marks)', () {
      final original = RadarRunDocument(
        metadata: RunMetadata(startedAt: DateTime.utc(2026)),
        series: const [],
        checkpoints: const [],
        nativeTimeline: nativeTimeline(),
      );
      final restored = RadarRunDocument.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );

      final native = restored.nativeTimeline;
      expect(native, isNotNull);
      expect(native!.columns.keys, {
        TriageColumn.nativePssKb,
        TriageColumn.threads,
      });
      final pss = native.columns[TriageColumn.nativePssKb]!;
      expect(pss.samples, hasLength(2));
      expect(pss.gaps.single.reason, 'process not running');
      expect(native.marks.single.label, 'start');
    });

    test('a run without native co-drive omits the key entirely', () {
      final json = RadarRunDocument(
        metadata: RunMetadata(startedAt: DateTime.utc(2026)),
        series: const [],
        checkpoints: const [],
      ).toJson();
      expect(json.containsKey('nativeTimeline'), isFalse);
    });

    test('an old run.json (no nativeTimeline) parses to a null lane', () {
      final restored = RadarRunDocument.fromJson({
        'schemaVersion': 1,
        'metadata': {'startedAt': '2026-07-17T09:30:15.000Z'},
        'series': const <Object?>[],
        'checkpoints': const <Object?>[],
      });
      expect(restored.nativeTimeline, isNull);
    });
  });
}
