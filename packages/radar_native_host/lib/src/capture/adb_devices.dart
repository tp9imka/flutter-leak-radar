/// One line of `adb devices -l` output.
class AdbDeviceLine {
  const AdbDeviceLine(this.serial, this.state, this.model);

  final String serial;

  /// e.g. `'device'`, `'unauthorized'`, `'offline'`.
  final String state;

  /// The value of the `model:<value>` token, if present.
  final String? model;
}

/// Parses `adb devices -l` stdout into [AdbDeviceLine]s.
///
/// Skips the `List of devices attached` header and blank lines. Each
/// remaining line is split on whitespace: the first cell is the serial,
/// the second is the state, and any `model:<value>` token supplies the
/// model.
List<AdbDeviceLine> parseAdbDevices(String stdout) => [
  for (final line in stdout.split('\n'))
    if (_parseDeviceLine(line) case final device?) device,
];

AdbDeviceLine? _parseDeviceLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || trimmed == 'List of devices attached') {
    return null;
  }
  final cells = trimmed.split(RegExp(r'\s+'));
  if (cells.length < 2) return null;

  String? model;
  for (final cell in cells.skip(2)) {
    if (cell.startsWith('model:')) {
      model = cell.substring('model:'.length);
      break;
    }
  }
  return AdbDeviceLine(cells[0], cells[1], model);
}
