import 'dart:convert';

import 'package:radar_workbench/radar_workbench.dart';

/// Ports `devtoolsPerfCallExtension` (see
/// `flutter_leak_radar_devtools/lib/src/adapters/devtools_perf_call.dart`)
/// to the desktop's own [RadarConnection] instead of DevTools'
/// `serviceManager`: calls [connection]'s owned `vmService` on its
/// `isolateRef`, unwrapping the `{"result": …}` envelope and mapping
/// "method not found" (-32601) to [ExtensionNotAvailableException]. This is
/// the desktop implementation of [PerfDataController]'s injectable
/// `callExtension`.
Future<Map<String, Object?>> desktopPerfCallExtension(
  RadarConnection connection,
  String method,
) async {
  final svc = connection.vmService;
  final isolateId = connection.isolateRef?.id;
  if (svc == null || isolateId == null) {
    throw const ExtensionNotAvailableException();
  }

  try {
    final response = await svc.callServiceExtension(
      method,
      isolateId: isolateId,
    );
    final json = response.json;
    if (json == null) {
      throw StateError('Extension returned null JSON for $method');
    }
    final result = json['result'];
    if (result is String) {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, Object?>) return decoded;
      return json.cast<String, Object?>();
    }
    return json.cast<String, Object?>();
  } on Exception catch (e) {
    if (e.toString().contains('-32601') ||
        e.toString().toLowerCase().contains('not found') ||
        e.toString().toLowerCase().contains('unknown method')) {
      throw const ExtensionNotAvailableException();
    }
    rethrow;
  }
}

/// Binds [connection] into a `Future<Map<String, Object?>> Function(String)`
/// suitable for [PerfDataController]'s `callExtension` constructor param.
Future<Map<String, Object?>> Function(String) perfCallFor(
  RadarConnection connection,
) =>
    (method) => desktopPerfCallExtension(connection, method);
