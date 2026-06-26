import '../model/span.dart';
import '../recorder/trace_recorder.dart';
import 'trace_clock.dart';

/// A handle to a manually started [Span].
///
/// Call [stop] when the operation completes successfully, or [fail]
/// when it throws. Only the first call to either method has effect —
/// the span is recorded once and the handle becomes inert afterward.
///
/// Forgetting to call either method is safe: the span is simply not
/// recorded, causing no leak or error.
final class SpanHandle {
  final Span _pendingSpan;
  final TraceRecorder _recorder;
  bool _done = false;

  /// Creates a [SpanHandle] for [pendingSpan]; its [Span.startMicros] marks
  /// the start on the shared tracer clock, against which the duration is
  /// measured when [stop]/[fail] is called.
  SpanHandle({required Span pendingSpan, required TraceRecorder recorder})
    : _pendingSpan = pendingSpan,
      _recorder = recorder;

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
    final finished = _pendingSpan.copyWith(
      durationMicros: traceClockNowMicros() - _pendingSpan.startMicros,
      status: status,
    );
    try {
      _recorder.record(finished);
    } catch (_) {
      // Recording must never throw into the host.
    }
  }
}
