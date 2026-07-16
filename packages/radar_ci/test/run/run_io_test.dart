import 'dart:convert';
import 'dart:io';

import 'package:radar_ci/radar_ci.dart';
import 'package:radar_ci/radar_ci_io.dart';
import 'package:test/test.dart';

void main() {
  group('flushPartialRun (interrupt cleanup)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('radar_ci_test_');
    });
    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test(
      'writes a partial, not-completed run.json from in-flight progress',
      () async {
        final progress = RunProgress()
          ..readings.add(
            const MemoryReading(
              tMicros: 0,
              heapUsed: 100,
              heapCapacity: 200,
              external: 0,
              rss: 1000,
            ),
          )
          ..checkpoints.add(
            const RunCheckpoint(
              tMicros: 0,
              label: 'start',
              allocationTopN: {'String': 3},
            ),
          );
        final outPath = '${tempDir.path}/run.json';

        final document = await flushPartialRun(
          progress: progress,
          metadata: RunMetadata(startedAt: DateTime.utc(2026)),
          outPath: outPath,
          abortReason: 'interrupted',
        );

        // Returned document reflects the partial state.
        expect(document.metadata.completed, isFalse);
        expect(document.metadata.abortReason, 'interrupted');

        // And it was actually written and re-reads as a valid partial run.
        final onDisk = RadarRunDocument.fromJson(
          jsonDecode(await File(outPath).readAsString())
              as Map<String, Object?>,
        );
        expect(onDisk.metadata.completed, isFalse);
        expect(onDisk.metadata.abortReason, 'interrupted');
        expect(onDisk.checkpoints.single.label, 'start');
        expect(
          onDisk.series.firstWhere((s) => s.name == 'dart.heap.used').samples,
          hasLength(1),
        );
      },
    );

    test('creates missing parent directories for the output path', () async {
      final outPath = '${tempDir.path}/nested/dir/run.json';
      await flushPartialRun(
        progress: RunProgress(),
        metadata: RunMetadata(startedAt: DateTime.utc(2026)),
        outPath: outPath,
        abortReason: 'interrupted',
      );
      expect(await File(outPath).exists(), isTrue);
    });
  });
}
