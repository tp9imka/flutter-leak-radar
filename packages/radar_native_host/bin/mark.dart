import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';

/// ```
/// dart run radar_native_host:radar_mark --session session_dir/ "reconnect"
/// ```
///
/// See [runMark] for the concurrency-safe mark append this thin entry point
/// delegates to.
Future<void> main(List<String> args) async => exit(await runMark(args));
