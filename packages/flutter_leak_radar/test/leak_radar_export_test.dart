// test/leak_radar_export_test.dart
import 'dart:io';

import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(LeakRadar.dispose);

  group('LeakRadar.exportToFile()', () {
    test('returns null when no report exists', () async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      final path = await LeakRadar.exportToFile();
      expect(path, isNull);
    });

    test('writes markdown file and returns absolute path', () async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      // Force a scan so latest is set.
      await LeakRadar.scan();
      final path = await LeakRadar.exportToFile(
        format: LeakExportFormat.markdown,
      );

      expect(path, isNotNull);
      expect(path, endsWith('.md'));
      final file = File(path!);
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('# Leak report'));
      file.deleteSync();
    });

    test('writes json file and returns absolute path', () async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      await LeakRadar.scan();
      final path = await LeakRadar.exportToFile(format: LeakExportFormat.json);

      expect(path, isNotNull);
      expect(path, endsWith('.json'));
      final file = File(path!);
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('"trigger"'));
      file.deleteSync();
    });

    test('returns null when disabled (no engine installed)', () async {
      // No engine installed — LeakRadar is in default disabled state.
      final path = await LeakRadar.exportToFile();
      expect(path, isNull);
    });

    test('writes file to the specified directory', () async {
      await LeakRadar.debugInstall(
        LeakEngine(
          probe: const NoopHeapProbe(),
          analyzer: LeakAnalyzer(SuspectSet.empty()),
        ),
      );
      await LeakRadar.scan();

      final tempDir = Directory.systemTemp.createTempSync('flr_export_test_');
      try {
        final path = await LeakRadar.exportToFile(
          format: LeakExportFormat.json,
          directory: tempDir,
        );
        expect(path, isNotNull);
        expect(path, startsWith(tempDir.path));
        expect(File(path!).existsSync(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
