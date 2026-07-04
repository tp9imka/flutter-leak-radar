// Gated end-to-end test: drives the REAL capture chain through the actual
// NativeProfilingController the UI uses — DeviceProbe -> AdbHeapprofdCapture
// (adb + heapprofd) -> pull -> validate -> PerfettoTraceImporter (trace_processor)
// -> summarizeByModule. Proves the desktop "Run device capture" flow works on a
// real device. Skips (passes) unless BOTH env vars are set, so CI stays green.
//
// Run locally against a connected device, e.g.:
//   RADAR_ADB_DEVICE=any \
//   RADAR_TP_BIN=../../.spikes/tools/trace_processor \
//   flutter test test/integration/real_capture_import_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/native_profiling_controller.dart';
import 'package:radar_desktop/src/seams/android/perfetto_trace_importer.dart';
import 'package:radar_native_host/radar_native_host.dart';

void main() {
  test(
    'captures from a device and imports into per-module summaries',
    () async {
      final adbDevice = Platform.environment['RADAR_ADB_DEVICE'];
      final tpBin = Platform.environment['RADAR_TP_BIN'];
      if (adbDevice == null || tpBin == null) {
        // ignore: avoid_print
        print('[skip] set RADAR_ADB_DEVICE and RADAR_TP_BIN to run this test');
        return;
      }

      final controller = NativeProfilingController(
        PerfettoTraceImporter(traceProcessorPath: () => tpBin),
        deviceProbe: const AdbDeviceProbe(ProcessAdbRunner()),
        capture: AdbHeapprofdCapture(const ProcessAdbRunner()),
      );

      await controller.refreshDevices();
      final ready = controller.devices.where((d) => d.isReady).toList();
      expect(ready, isNotEmpty, reason: 'no ready adb device');
      final serial = adbDevice == 'any' ? ready.first.serial : adbDevice;

      await controller.captureAndImport(
        CaptureRequest(
          packageId: 'com.katim.leak_lab',
          mode: CaptureMode.startup,
          durationMs: 12000,
          serial: serial,
        ),
      );

      expect(
        controller.captureState,
        CaptureState.idle,
        reason: controller.captureError ?? controller.errorMessage ?? 'failed',
      );
      expect(controller.checkpoints, hasLength(1));
      final summaries = controller.selectedSummaries;
      expect(summaries, isNotEmpty);
      expect(controller.selectedTotalStillLiveBytes, greaterThan(0));

      // ignore: avoid_print
      print('captured+imported; top still-live modules:');
      for (final s in summaries.take(6)) {
        // ignore: avoid_print
        print('  ${s.module}  ${s.stillLiveBytes} B  (${s.kind.name})');
      }

      controller.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
