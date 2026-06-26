import 'dart:async';

import '../model/span.dart';
import '../recorder/trace_recorder.dart';
import '../snapshot/trace_snapshot.dart';
import 'active_span.dart';
import 'span_handle.dart';

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
/// across `await` boundaries.
///
/// Recording errors are swallowed internally — the host always
/// receives its body result or exception unmodified.
final class Tracer {
  /// The [TraceRecorder] used to aggregate finished spans.
  final TraceRecorder recorder;

  /// Creates a [Tracer].
  ///
  /// If [recorder] is omitted, a default [TraceRecorder] is used.
  Tracer({TraceRecorder? recorder})
      : recorder = recorder ?? TraceRecorder();

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
  }) {
    final stopwatch = Stopwatch()..start();
    final parentSpan = activeSpan;
    final spanId = SpanId.generate();
    final traceId = parentSpan?.traceId ?? spanId;
    final pending = Span(
      spanId: spanId,
      parentId: parentSpan?.spanId,
      traceId: traceId,
      name: name,
      category: category,
      startMicros: stopwatch.elapsedMicroseconds,
      durationMicros: 0,
      status: SpanStatus.ok,
      attributes: attributes ?? const {},
    );

    T result;
    SpanStatus status;
    try {
      result = Zone.current
          .fork(zoneValues: {kActiveSpanKey: pending})
          .run(body);
      status = SpanStatus.ok;
    } catch (_) {
      stopwatch.stop();
      _safeRecord(
        pending.copyWith(
          durationMicros: stopwatch.elapsedMicroseconds,
          status: SpanStatus.error,
        ),
      );
      rethrow;
    }
    stopwatch.stop();
    _safeRecord(
      pending.copyWith(
        durationMicros: stopwatch.elapsedMicroseconds,
        status: status,
      ),
    );
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
  }) async {
    final stopwatch = Stopwatch()..start();
    final parentSpan = activeSpan;
    final spanId = SpanId.generate();
    final traceId = parentSpan?.traceId ?? spanId;
    final pending = Span(
      spanId: spanId,
      parentId: parentSpan?.spanId,
      traceId: traceId,
      name: name,
      category: category,
      startMicros: stopwatch.elapsedMicroseconds,
      durationMicros: 0,
      status: SpanStatus.ok,
      attributes: attributes ?? const {},
    );

    T result;
    SpanStatus status;
    try {
      result = await Zone.current
          .fork(zoneValues: {kActiveSpanKey: pending})
          .run(() => body());
      status = SpanStatus.ok;
    } catch (_) {
      stopwatch.stop();
      _safeRecord(
        pending.copyWith(
          durationMicros: stopwatch.elapsedMicroseconds,
          status: SpanStatus.error,
        ),
      );
      rethrow;
    }
    stopwatch.stop();
    _safeRecord(
      pending.copyWith(
        durationMicros: stopwatch.elapsedMicroseconds,
        status: status,
      ),
    );
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
  }) {
    final stopwatch = Stopwatch()..start();
    final parentSpan = activeSpan;
    final spanId = SpanId.generate();
    final traceId = parentSpan?.traceId ?? spanId;
    final pending = Span(
      spanId: spanId,
      parentId: parentSpan?.spanId,
      traceId: traceId,
      name: name,
      category: category,
      startMicros: stopwatch.elapsedMicroseconds,
      durationMicros: 0,
      status: SpanStatus.ok,
      attributes: attributes ?? const {},
    );
    return SpanHandle(
      pendingSpan: pending,
      recorder: recorder,
      stopwatch: stopwatch,
    );
  }

  /// Returns an immutable snapshot of all aggregated statistics.
  TraceSnapshot snapshot() => recorder.snapshot();

  void _safeRecord(Span span) {
    try {
      recorder.record(span);
    } catch (_) {
      // Recording errors must never propagate to the host.
    }
  }
}
