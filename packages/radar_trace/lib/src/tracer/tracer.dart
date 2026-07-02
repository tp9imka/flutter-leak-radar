import 'dart:async';

import '../model/span.dart';
import '../recorder/trace_recorder.dart';
import '../snapshot/trace_snapshot.dart';
import 'active_span.dart';
import 'span_handle.dart';
import 'trace_clock.dart';

/// Ergonomic façade for recording [Span]s.
///
/// The three entry points cover all common instrumentation patterns:
///
/// - [trace] wraps a synchronous body.
/// - [traceAsync] wraps an asynchronous body (Future).
/// - [start] returns a [SpanHandle] for manual start/stop across
///   callback or zone boundaries.
///
/// All three propagate the current span via the ambient [Zone] so
/// that nested calls automatically set [Span.parentId] correctly
/// across `await` boundaries. Span start times and durations come from
/// the shared [traceClockNowMicros] clock, so spans are comparable.
///
/// Recording errors are swallowed internally — the host always
/// receives its body result or exception unmodified.
final class Tracer {
  /// The [TraceRecorder] used to aggregate finished spans.
  final TraceRecorder recorder;

  /// Creates a [Tracer].
  ///
  /// If [recorder] is omitted, a default [TraceRecorder] is used.
  Tracer({TraceRecorder? recorder}) : recorder = recorder ?? TraceRecorder();

  /// Measures [body] synchronously and records a [Span].
  ///
  /// Returns the body's return value. If [body] throws, the exception
  /// propagates to the caller after the span is recorded with
  /// [SpanStatus.error].
  T trace<T>(
    String name,
    T Function() body, {
    String? category,
    Map<String, Object?>? attributes,
    List<String>? dedupKey,
  }) {
    final startMicros = traceClockNowMicros();
    final pending = _begin(name, category, attributes, startMicros, dedupKey);

    T result;
    try {
      result = Zone.current
          .fork(zoneValues: {kActiveSpanKey: pending})
          .run(body);
    } catch (_) {
      _end(pending, startMicros, SpanStatus.error);
      rethrow;
    }
    _end(pending, startMicros, SpanStatus.ok);
    return result;
  }

  /// Measures [body] asynchronously and records a [Span] when the
  /// returned [Future] completes.
  ///
  /// Returns the body's value. If the [Future] throws, the exception
  /// propagates to the caller after the span is recorded with
  /// [SpanStatus.error].
  Future<T> traceAsync<T>(
    String name,
    Future<T> Function() body, {
    String? category,
    Map<String, Object?>? attributes,
    List<String>? dedupKey,
  }) async {
    final startMicros = traceClockNowMicros();
    final pending = _begin(name, category, attributes, startMicros, dedupKey);

    T result;
    try {
      result = await Zone.current
          .fork(zoneValues: {kActiveSpanKey: pending})
          .run(() => body());
    } catch (_) {
      _end(pending, startMicros, SpanStatus.error);
      rethrow;
    }
    _end(pending, startMicros, SpanStatus.ok);
    return result;
  }

  /// Returns a [SpanHandle] for a manually bounded measurement.
  ///
  /// The caller must call [SpanHandle.stop] or [SpanHandle.fail] to
  /// record the span. Forgetting to stop is safe — the span is simply
  /// not recorded.
  SpanHandle start(
    String name, {
    String? category,
    Map<String, Object?>? attributes,
    List<String>? dedupKey,
  }) {
    final pending = _begin(
      name,
      category,
      attributes,
      traceClockNowMicros(),
      dedupKey,
    );
    return SpanHandle(pendingSpan: pending, recorder: recorder);
  }

  /// Returns an immutable snapshot of all aggregated statistics.
  TraceSnapshot snapshot() => recorder.snapshot();

  /// Builds the pending span, parented to the ambient active span.
  Span _begin(
    String name,
    String? category,
    Map<String, Object?>? attributes,
    int startMicros,
    List<String>? dedupKey,
  ) {
    final parentSpan = activeSpan;
    final spanId = SpanId.generate();
    return Span(
      spanId: spanId,
      parentId: parentSpan?.spanId,
      traceId: parentSpan?.traceId ?? spanId,
      name: name,
      category: category,
      startMicros: startMicros,
      durationMicros: 0,
      status: SpanStatus.ok,
      attributes: attributes ?? const {},
      dedupKey: (dedupKey == null || dedupKey.isEmpty)
          ? null
          : dedupKey.join(','),
    );
  }

  /// Records [pending] with its measured duration and final [status].
  void _end(Span pending, int startMicros, SpanStatus status) {
    _safeRecord(
      pending.copyWith(
        durationMicros: traceClockNowMicros() - startMicros,
        status: status,
      ),
    );
  }

  void _safeRecord(Span span) {
    try {
      recorder.record(span);
    } catch (_) {
      // Recording errors must never propagate to the host.
    }
  }
}
