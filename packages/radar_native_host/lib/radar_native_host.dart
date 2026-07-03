/// Host-side Perfetto/heapprofd parser and `adb` capture control (Lane B
/// host tooling).
///
/// Shells out to an external `traceconv`/`perfetto` binary to turn
/// `.pftrace` captures into `radar_native` model checkpoints, and to
/// `adb` to drive on-device heapprofd capture sessions. Unlike the
/// pure-Dart `radar_native` package, this package may use `dart:io`.
/// Exports are added incrementally as each parser lands.
library;

export 'src/capture/adb_devices.dart';
export 'src/capture/adb_runner.dart';
export 'src/capture/device_probe.dart';
export 'src/capture/heapprofd_config.dart';
export 'src/capture/native_heap_capture.dart';
export 'src/perfetto/perfetto_profile_mapper.dart';
export 'src/perfetto/perfetto_row.dart';
export 'src/perfetto/perfetto_sql.dart';
export 'src/perfetto/perfetto_trace_processor_parser.dart';
export 'src/perfetto/trace_processor_runner.dart';
export 'src/symbolize/build_id_reader.dart';
export 'src/symbolize/symbol_store_builder.dart';
export 'src/symbolize/symbolize_cli.dart';
export 'src/symbolize/symbolizer.dart';
