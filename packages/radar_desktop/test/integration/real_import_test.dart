// Gated end-to-end test: drives the REAL PerfettoTraceImporter through the
// NativeProfilingController against a real .pftrace, proving the full desktop
// import chain (trace_processor -> parse -> summarize by module) works on real
// device data. Skips (passes) unless both env vars are set, so CI stays green.
//
// Run locally, e.g.:
//   RADAR_TP_BIN=../../.spikes/tools/trace_processor \
//   RADAR_TP_TRACE=../../.spikes/captures/leaklab.pftrace \
//   flutter test test/integration/real_import_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/seams/android/perfetto_trace_importer.dart';

void main() {
  test(
    'imports a real .pftrace into non-empty per-module still-live summaries',
    () async {
      final bin = Platform.environment['RADAR_TP_BIN'];
      final trace = Platform.environment['RADAR_TP_TRACE'];
      if (bin == null || trace == null) {
        // ignore: avoid_print
        print('[skip] set RADAR_TP_BIN and RADAR_TP_TRACE to run this test');
        return;
      }

      final controller = NativeProfilingController(
        PerfettoTraceImporter(traceProcessorPath: () => bin),
      );
      await controller.importTrace(trace, label: 'real');

      expect(
        controller.state,
        NativeImportState.idle,
        reason: controller.errorMessage ?? 'import failed',
      );
      expect(controller.checkpoints, hasLength(1));
      final summaries = controller.selectedSummaries;
      expect(summaries, isNotEmpty);
      expect(controller.selectedTotalStillLiveBytes, greaterThan(0));

      // Print the top modules so the run surfaces the real attribution (e.g.
      // base.apk ~10 MB for the leak-lab known-leak capture).
      // ignore: avoid_print
      print('top still-live modules:');
      for (final s in summaries.take(6)) {
        // ignore: avoid_print
        print('  ${s.module}  ${s.stillLiveBytes} B  (${s.kind.name})');
      }

      controller.dispose();
    },
  );
}
