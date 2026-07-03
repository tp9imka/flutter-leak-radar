import 'package:radar_native/radar_native.dart';

import 'perfetto_profile_mapper.dart';
import 'trace_processor_runner.dart';

/// Thin async facade wiring a [TraceProcessorRunner] into a
/// [PerfettoProfileMapper]: runs the query, then maps the resulting rows
/// into a [NativeHeapProfile] checkpoint.
final class PerfettoTraceProcessorParser {
  const PerfettoTraceProcessorParser(this._runner);

  final TraceProcessorRunner _runner;

  /// Runs the runner over [tracePath] and maps the rows into a checkpoint.
  Future<NativeHeapProfile> parseTrace(
    String tracePath, {
    required DateTime capturedAt,
    String label = '',
    NativeProfileMeta meta = const NativeProfileMeta(),
  }) async {
    final rows = await _runner.query(tracePath);
    return PerfettoProfileMapper(
      capturedAt: capturedAt,
      meta: meta,
    ).parse(rows, label: label);
  }
}
