// example/lib/self_test_extension.dart
//
// Registers `ext.radarscope.selftest` — a VM service extension that drives the
// live leak scenario ([runLeakSelfTest]) on demand. This gives
// `radar_ci run --call-extension ext.radarscope.selftest` a real target to fire
// between checkpoints, so the headless CI front door can exercise the very
// leak the in-app self-test triggers.
//
// Naming follows the repo's `ext.<package>.<action>` convention (see
// flutter_perf_radar's `ext.perf_radar.snapshot`).
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'leak_self_test.dart';

/// Guards against double-registration across hot restarts.
bool _registered = false;

/// Registers `ext.radarscope.selftest`, resolving the live [NavigatorState]
/// from [navigatorKey] at call time.
///
/// A no-op in release builds (where VM service extensions are unavailable) and
/// idempotent. The extension responds `{"ran": true}` after one full
/// open/pop/scan cycle, or a structured error when no navigator is mounted yet
/// or the self-test throws — it never crashes the host app.
void registerSelfTestExtension(GlobalKey<NavigatorState> navigatorKey) {
  if (kReleaseMode) return;
  if (_registered) return;
  _registered = true;

  developer.registerExtension('ext.radarscope.selftest', (
    method,
    params,
  ) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'ext.radarscope.selftest: no navigator mounted yet',
      );
    }
    try {
      await runLeakSelfTest(navigator);
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'ran': true}),
      );
    } catch (error, stackTrace) {
      developer.log(
        'ext.radarscope.selftest failed: $error',
        name: 'radarscope.example',
        error: error,
        stackTrace: stackTrace,
      );
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'ext.radarscope.selftest failed: $error',
      );
    }
  });
}
