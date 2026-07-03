import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

void main() {
  test(
    'captures a real .pftrace from a connected device',
    () async {
      final want = Platform.environment['RADAR_ADB_DEVICE'];
      if (want == null) {
        print(
          '[skip] set RADAR_ADB_DEVICE (a serial or "any") to run this '
          'test',
        );
        return;
      }

      final devices = await const AdbDeviceProbe(ProcessAdbRunner()).probe();
      final ready = devices.where((d) => d.isReady).toList();
      expect(ready, isNotEmpty, reason: 'no ready adb device');
      final serial = want == 'any' ? ready.first.serial : want;

      final out =
          '${Directory.systemTemp.createTempSync('radar_cap').path}/'
          'real.pftrace';
      final path = await AdbHeapprofdCapture(const ProcessAdbRunner()).capture(
        CaptureRequest(
          packageId: 'com.katim.leak_lab',
          mode: CaptureMode.startup,
          durationMs: 12000,
          serial: serial,
        ),
        outputPath: out,
      );

      final f = File(path);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1024));
      print('[ok] captured ${f.lengthSync()} bytes to $path');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
