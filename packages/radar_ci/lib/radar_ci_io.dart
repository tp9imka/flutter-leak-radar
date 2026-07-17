/// `dart:io`-backed entry points for the `radar_ci` CLI.
///
/// Kept out of the pure `package:radar_ci/radar_ci.dart` barrel so the model
/// and parsing surface stays importable from non-io contexts (tests, tools).
library;

export 'src/gate/gate_command.dart';
export 'src/report/report_command.dart';
export 'src/run/run_io.dart';
