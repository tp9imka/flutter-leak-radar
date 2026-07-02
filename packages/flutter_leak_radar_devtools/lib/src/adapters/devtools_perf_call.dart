import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:radar_workbench/radar_workbench.dart';

/// Calls a VM service extension via DevTools' [serviceManager] on the main
/// isolate, unwrapping the `{"result": …}` envelope and mapping "method not
/// found" (-32601) to [ExtensionNotAvailableException]. This is the DevTools
/// implementation of [PerfDataController]'s injectable `callExtension`.
Future<Map<String, Object?>> devtoolsPerfCallExtension(String method) async {
  final svc = serviceManager.service;
  if (svc == null) throw const ExtensionNotAvailableException();
  final isolateId = serviceManager.isolateManager.mainIsolate.value?.id;
  if (isolateId == null) throw const ExtensionNotAvailableException();

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
