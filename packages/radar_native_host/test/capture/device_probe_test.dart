import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

const _readySerial = 'DG2LHD1450610066';
const _unauthorizedSerial = 'EMULATOR_SERIAL';
const _fallbackSerial = 'FALLBACK_SERIAL';

const _cannedDevicesOutput =
    'List of devices attached\n'
    '$_readySerial       device usb:1-1 product:sadeem model:KATIM_X3M '
    'device:sadeem transport_id:10\n'
    '$_unauthorizedSerial\tunauthorized\n'
    '$_fallbackSerial       device usb:1-2 product:sadeem '
    'model:FALLBACK_MODEL device:sadeem transport_id:11\n'
    '\n';

const _getpropRepliesBySerial = {
  _readySerial: {
    'ro.product.model': 'KATIM X3M\n',
    'ro.build.version.release': '15\n',
    'ro.build.type': 'userdebug\n',
  },
  _fallbackSerial: {
    'ro.product.model': '\n',
    'ro.build.version.release': '14\n',
    'ro.build.type': 'user\n',
  },
};

class _AdbCall {
  const _AdbCall(this.args, this.serial);

  final List<String> args;
  final String? serial;
}

class _FakeAdbRunner implements AdbRunner {
  final calls = <_AdbCall>[];

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    calls.add(_AdbCall(args, serial));
    if (args case ['devices', '-l']) {
      return const AdbResult(0, _cannedDevicesOutput, '');
    }
    if (args case ['shell', 'getprop', final prop]) {
      final reply = _getpropRepliesBySerial[serial]?[prop];
      if (reply != null) return AdbResult(0, reply, '');
    }
    return AdbResult(1, '', 'unexpected call: $args (serial: $serial)');
  }
}

void main() {
  group('AdbDeviceProbe', () {
    test('enriches the ready device and skips the unauthorized one', () async {
      final runner = _FakeAdbRunner();
      final probe = AdbDeviceProbe(runner);

      final devices = await probe.probe();

      expect(devices, hasLength(3));

      final ready = devices[0];
      expect(ready.serial, _readySerial);
      expect(ready.isReady, isTrue);
      expect(ready.model, 'KATIM X3M');
      expect(ready.androidRelease, '15');
      expect(ready.buildType, 'userdebug');
      expect(ready.label, 'KATIM X3M · android 15');

      final unauthorized = devices[1];
      expect(unauthorized.serial, _unauthorizedSerial);
      expect(unauthorized.isReady, isFalse);
      expect(unauthorized.model, isNull);
      expect(unauthorized.androidRelease, isNull);
      expect(unauthorized.buildType, isNull);

      final getpropCallsForUnauthorized = runner.calls.where(
        (c) => c.serial == _unauthorizedSerial,
      );
      expect(getpropCallsForUnauthorized, isEmpty);
    });

    test('falls back to the adb devices model token when getprop model '
        'is empty', () async {
      final runner = _FakeAdbRunner();
      final probe = AdbDeviceProbe(runner);

      final devices = await probe.probe();

      final fallback = devices.firstWhere((d) => d.serial == _fallbackSerial);
      expect(fallback.model, 'FALLBACK_MODEL');
      expect(fallback.androidRelease, '14');
      expect(fallback.buildType, 'user');
    });
  });
}
