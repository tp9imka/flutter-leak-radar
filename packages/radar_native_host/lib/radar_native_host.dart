/// Host-side Perfetto/heapprofd parser (Lane B host tooling).
///
/// Shells out to an external `traceconv`/`perfetto` binary to turn
/// `.pftrace` captures into `radar_native` model checkpoints. Unlike the
/// pure-Dart `radar_native` package, this package may use `dart:io`.
/// Exports are added incrementally as each parser lands.
library;

export 'src/perfetto/perfetto_profile_mapper.dart';
export 'src/perfetto/perfetto_row.dart';
