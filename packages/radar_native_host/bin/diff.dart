import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';

/// ```
/// dart run radar_native_host:radar_diff before.pftrace after.pftrace \
///   [--format json|md] [--tp-bin trace_processor]
/// ```
///
/// See [runDiff] for the per-module/per-callsite still-live ranking this thin
/// entry point delegates to.
Future<void> main(List<String> args) async => exit(await runDiff(args));
