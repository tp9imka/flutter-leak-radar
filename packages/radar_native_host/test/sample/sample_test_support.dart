import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';

/// Reads a captured device-output fixture by [name] from `fixtures/`.
///
/// Resolved relative to the package root, matching how the suite is run
/// (`dart test` with the package as the working directory).
String fixture(String name) =>
    File('test/sample/fixtures/$name').readAsStringSync();

/// An [AdbRunner] that returns one fixed [AdbResult] and records every call.
class FixedAdbRunner implements AdbRunner {
  FixedAdbRunner(this.result);

  /// The result returned for every [run].
  final AdbResult result;

  /// The args of each call, in order.
  final List<List<String>> calls = [];

  @override
  Future<AdbResult> run(List<String> args, {String? serial, String? stdin}) {
    calls.add(args);
    return Future.value(result);
  }
}

/// An [AdbRunner] whose result is chosen per call by [route], for exercising a
/// [CompositeSampler] over several on-device commands with one seam.
class ScriptedAdbRunner implements AdbRunner {
  ScriptedAdbRunner(this.route);

  /// Maps a call's args to the [AdbResult] to return.
  final AdbResult Function(List<String> args) route;

  /// The args of each call, in order.
  final List<List<String>> calls = [];

  @override
  Future<AdbResult> run(List<String> args, {String? serial, String? stdin}) {
    calls.add(args);
    return Future.value(route(args));
  }
}

/// A successful [AdbResult] carrying [stdout].
AdbResult ok(String stdout) => AdbResult(0, stdout, '');

/// A failed [AdbResult] (dead pid / permission), exit [code] with [stderr].
AdbResult failed({int code = 1, String stderr = 'error'}) =>
    AdbResult(code, '', stderr);
