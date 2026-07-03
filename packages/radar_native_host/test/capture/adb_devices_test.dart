import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

const _cannedDevicesOutput =
    'List of devices attached\n'
    'DG2LHD1450610066       device usb:1-1 product:sadeem model:KATIM_X3M '
    'device:sadeem transport_id:10\n'
    'EMULATOR_SERIAL\tunauthorized\n'
    '\n';

void main() {
  group('parseAdbDevices', () {
    test('parses device and unauthorized lines, extracting model', () {
      final devices = parseAdbDevices(_cannedDevicesOutput);

      expect(devices, hasLength(2));
      expect(devices[0].serial, 'DG2LHD1450610066');
      expect(devices[0].state, 'device');
      expect(devices[0].model, 'KATIM_X3M');
      expect(devices[1].serial, 'EMULATOR_SERIAL');
      expect(devices[1].state, 'unauthorized');
      expect(devices[1].model, isNull);
    });

    test('returns an empty list for header-only output', () {
      expect(parseAdbDevices('List of devices attached\n\n'), isEmpty);
    });
  });
}
