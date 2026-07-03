import 'adb_devices.dart';
import 'adb_runner.dart';

/// A connected Android device, optionally enriched with `getprop`
/// details when it is in the ready (`'device'`) state.
class AndroidDevice {
  const AndroidDevice({
    required this.serial,
    required this.state,
    this.model,
    this.androidRelease,
    this.buildType,
  });

  final String serial;

  /// `'device'`, `'unauthorized'`, or `'offline'`.
  final String state;

  final String? model;
  final String? androidRelease;
  final String? buildType;

  /// Whether the device is authorized and ready to accept commands.
  bool get isReady => state == 'device';

  /// A human-readable label, e.g. `'KATIM X3M · android 15'`.
  String get label => [
    model ?? serial,
    if (androidRelease != null) 'android $androidRelease',
  ].join(' · ');
}

/// Lists connected Android devices.
abstract interface class DeviceProbe {
  Future<List<AndroidDevice>> probe();
}

/// [DeviceProbe] backed by `adb devices -l`, with per-device `getprop`
/// enrichment for devices that are ready to accept commands.
final class AdbDeviceProbe implements DeviceProbe {
  const AdbDeviceProbe(this._runner);

  final AdbRunner _runner;

  @override
  Future<List<AndroidDevice>> probe() async {
    final result = await _runner.run(['devices', '-l']);
    final lines = parseAdbDevices(result.stdout);

    final devices = <AndroidDevice>[];
    for (final line in lines) {
      devices.add(
        line.state == 'device'
            ? await _enrich(line)
            : AndroidDevice(
                serial: line.serial,
                state: line.state,
                model: line.model,
              ),
      );
    }
    return devices;
  }

  /// Enriches a ready device with model, Android release, and build
  /// type via serial-scoped `getprop` calls.
  Future<AndroidDevice> _enrich(AdbDeviceLine line) async {
    final model = await _getprop(line.serial, 'ro.product.model');
    final release = await _getprop(line.serial, 'ro.build.version.release');
    final buildType = await _getprop(line.serial, 'ro.build.type');
    return AndroidDevice(
      serial: line.serial,
      state: line.state,
      model: model.isNotEmpty ? model : line.model,
      androidRelease: release.isNotEmpty ? release : null,
      buildType: buildType.isNotEmpty ? buildType : null,
    );
  }

  Future<String> _getprop(String serial, String property) async {
    final result = await _runner.run([
      'shell',
      'getprop',
      property,
    ], serial: serial);
    return result.stdout.trim();
  }
}
