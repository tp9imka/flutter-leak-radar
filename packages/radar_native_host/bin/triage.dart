import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';

/// ```
/// dart run radar_native_host:radar_triage session_dir/ [--format json|md]
/// dart run radar_native_host:radar_triage before_dir/ --compare after_dir/ \
///   [--format json|md]
/// ```
///
/// See [runTriage] for the router-summary + per-column table (and the
/// before-vs-after compare) this thin entry point delegates to.
Future<void> main(List<String> args) async => exit(await runTriage(args));
