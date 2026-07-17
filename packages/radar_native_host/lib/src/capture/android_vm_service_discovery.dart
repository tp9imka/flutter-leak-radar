import 'adb_runner.dart';

/// Matches Flutter's own `flutter attach` VM-service discovery regex,
/// verbatim, so any logcat line Flutter itself recognizes is recognized
/// here too.
final _dartVmServiceRegExp = RegExp(
  r'The Dart VM service is listening on '
  r'((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)',
);

/// Matches the modern `A Dart VM Service on <device> is available at: <url>`
/// wording newer `flutter run`/`flutter attach` prints (the device name may
/// contain spaces). Neither the `listening on` nor `Observatory` regex above
/// matches it, so without this a first-time user's flagship spawn path never
/// discovers the URI and times out.
final _dartVmServiceAvailableRegExp = RegExp(
  r'A Dart VM Service on .+ is available at:\s*'
  r'((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)',
);

/// Tolerates the older `Observatory listening on <url>` wording emitted
/// by pre-VM-service Flutter builds.
final _observatoryRegExp = RegExp(
  r'Observatory listening on ((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)',
);

/// A VM-service endpoint parsed from `adb logcat`, on the device side.
final class DeviceVmServiceUri {
  const DeviceVmServiceUri({
    required this.host,
    required this.port,
    required this.path,
  });

  /// Usually `127.0.0.1`.
  final String host;

  /// The DEVICE-side port; not reachable from the host until forwarded.
  final int port;

  /// The token-bearing path, e.g. `'/GJur1BL3JL4=/'`. May be empty.
  final String path;
}

/// Extracts VM-service URIs from raw `adb logcat` text, in the order
/// they appear (first→last). The caller takes `.last` for the newest
/// match, since a device may accumulate lines from earlier runs.
List<DeviceVmServiceUri> parseLogcatVmServiceUris(String logcat) => [
  for (final line in logcat.split('\n'))
    if (_parseLine(line) case final uri?) uri,
];

DeviceVmServiceUri? _parseLine(String line) {
  final match =
      _dartVmServiceRegExp.firstMatch(line) ??
      _dartVmServiceAvailableRegExp.firstMatch(line) ??
      _observatoryRegExp.firstMatch(line);
  if (match == null) return null;

  final uri = Uri.tryParse(match.group(1)!);
  if (uri == null || uri.host.isEmpty) return null;

  return DeviceVmServiceUri(host: uri.host, port: uri.port, path: uri.path);
}

/// Scans `adb logcat` for a device's Flutter VM-service URI and
/// `adb forward`s its device-side port to the host, mirroring how
/// `flutter attach` discovers Android apps.
final class AndroidVmServiceDiscovery {
  const AndroidVmServiceDiscovery(this._adb);

  final AdbRunner _adb;

  /// Runs `adb [-s serial] logcat -d` and parses the dump for
  /// VM-service URIs, in first→last order.
  Future<List<DeviceVmServiceUri>> scan({String? serial}) async {
    final result = await _adb.run(['logcat', '-d'], serial: serial);
    return parseLogcatVmServiceUris(result.stdout);
  }

  /// Runs `adb [-s serial] forward tcp:0 tcp:<devicePort>` and returns
  /// the host port `adb` assigned, which it prints on stdout.
  ///
  /// Throws a [StateError] if `adb` did not print a plain port number.
  Future<int> forward(int devicePort, {String? serial}) async {
    final result = await _adb.run([
      'forward',
      'tcp:0',
      'tcp:$devicePort',
    ], serial: serial);

    final hostPort = int.tryParse(result.stdout.trim());
    if (hostPort == null) {
      throw StateError(
        'adb forward did not report a host port for device port '
        "$devicePort: stdout='${result.stdout}' stderr='${result.stderr}'",
      );
    }
    return hostPort;
  }

  /// Scans for the newest VM-service URI, forwards its device port, and
  /// builds a ready-to-connect `ws://127.0.0.1:<hostPort>/…/ws` URI.
  ///
  /// Returns `null` if no VM-service line was found in the logcat dump.
  Future<String?> discoverWsUri({String? serial}) async {
    final uris = await scan(serial: serial);
    if (uris.isEmpty) return null;

    final newest = uris.last;
    final hostPort = await forward(newest.port, serial: serial);
    return 'ws://127.0.0.1:$hostPort${_wsPath(newest.path)}';
  }
}

/// Normalizes [path] to end with exactly one `/ws` segment, regardless
/// of whether it already ends with `/ws`, `/ws/`, or neither.
String _wsPath(String path) {
  final withTrailingSlash = path.endsWith('/') ? path : '$path/';
  return withTrailingSlash.endsWith('/ws/')
      ? withTrailingSlash.substring(0, withTrailingSlash.length - 1)
      : '${withTrailingSlash}ws';
}
