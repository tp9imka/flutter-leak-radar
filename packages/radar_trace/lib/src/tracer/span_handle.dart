import '../model/span.dart';
import '../recorder/trace_recorder.dart';

/// A handle to a manually started [Span].
///
/// Call [stop] when the operation completes successfully, or [fail]
/// when it throws. Only the first call to either method has effect —
/// the span is recorded once and the handle becomes inert afterward.
///
/// Forgetting to call either method is safe: the span is simply not
/// recorded, causing no leak or error.
final class SpanHandle {
  final Stopwatch _stopwatch;
  final Span _pendingSpan;
  final TraceRecorder _recorder;
  bool _done = false;

  /// Creates a [SpanHandle].
  ///
  /// The [stopwatch] must already be started at the point the logical
  /// operation began.
  SpanHandle({
    required Span pendingSpan,
    required TraceRecorder recorder,
    required Stopwatch stopwatch,
  })  : _pendingSpan = pendingSpan,
        _recorder = recorder,
        _stopwatch = stopwatch;

  /// The in-progress span. [Span.durationMicros] is 0 until stopped.
  Span get span => _pendingSpan;

  /// Records the span with [SpanStatus.ok].
  ///
  /// Subsequent calls are no-ops.
  void stop() => _finish(SpanStatus.ok);

  /// Records the span with [SpanStatus.error].
  ///
  /// Subsequent calls are no-ops.
  void fail([Object? error]) => _finish(SpanStatus.error);

  void _finish(SpanStatus status) {
    if (_done) return;
    _done = true;
    _stopwatch.stop();
    final finished = _pendingSpan.copyWith(
      durationMicros: _stopwatch.elapsedMicroseconds,
      status: status,
    );
    try {
      _recorder.record(finished);
    } catch (_) {
      // Recording must never throw into the host.
    }
  }
}
