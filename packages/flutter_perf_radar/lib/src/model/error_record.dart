import 'package:meta/meta.dart';

/// An immutable record of one captured error event.
@immutable
final class ErrorRecord {
  const ErrorRecord({
    required this.message,
    required this.clockMicros,
    this.context,
    this.stackTraceString,
  });

  /// Human-readable error message derived from the thrown object.
  final String message;

  /// Optional label from the capture site (e.g. `'FlutterError'`).
  final String? context;

  /// Monotonic clock time (from [traceClockNowMicros]) at capture.
  final int clockMicros;

  /// Stack trace as a string, or null if not available.
  final String? stackTraceString;
}
