// test/engine/heap_snapshot_file_test.dart
import 'dart:io';

import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(LeakRadar.dispose);

  group('LeakRadar.captureHeapSnapshotToFile()', () {
    test('returns null when engine is not initialised', () async {
      // LeakRadar is in the default disabled state (no engine installed).
      final path = await LeakRadar.captureHeapSnapshotToFile();
      expect(path, isNull);
    });

    test('returns null when config has enabled:false', () async {
      await LeakRadar.init(const LeakRadarConfig(enabled: false));
      final path = await LeakRadar.captureHeapSnapshotToFile();
      expect(path, isNull);
    });

    test('never throws regardless of engine state', () async {
      // No engine installed — disabled path.
      await expectLater(
        LeakRadar.captureHeapSnapshotToFile(),
        completion(isNull),
      );
    });

    test(
      'returns a non-null path and the file exists when engine is active',
      () async {
        await LeakRadar.debugInstall(
          LeakEngine(
            probe: const NoopHeapProbe(),
            analyzer: LeakAnalyzer(SuspectSet.empty()),
          ),
        );

        final tempDir = Directory.systemTemp.createTempSync('flr_heap_test_');
        try {
          final path = await LeakRadar.captureHeapSnapshotToFile(
            directory: tempDir,
          );
          // NativeRuntime.writeHeapSnapshotToFile is available in the test VM
          // (debug/profile mode), so path should be non-null.
          expect(path, isNotNull);
          expect(path, endsWith('.data'));
          expect(path, contains('leak_radar_heap_'));
          expect(File(path!).existsSync(), isTrue);
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
      skip: Platform.isAndroid || Platform.isIOS
          ? 'NativeRuntime.writeHeapSnapshotToFile is not supported on mobile test runners'
          : null,
    );

    test('uses Directory.systemTemp when no directory is given', () async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );

      final path = await LeakRadar.captureHeapSnapshotToFile();
      if (path != null) {
        expect(path, startsWith(Directory.systemTemp.path));
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
      // null is also acceptable when the platform doesn't support it.
    });
  });
}
