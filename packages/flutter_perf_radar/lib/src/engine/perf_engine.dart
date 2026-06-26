// Copyright (c) 2025, tp9imka. All rights reserved.

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:radar_trace/radar_trace.dart';

import '../config/perf_radar_config.dart';
import '../model/frame_stats.dart';
import '../model/stability_snapshot.dart';
import 'frame_collector.dart';
import 'stability_recorder.dart';
import 'stall_watchdog.dart';

/// Central engine that owns all perf data collection.
///
/// Start with [start], stop with [stop]. Call [trace]/[traceAsync]/[startSpan]
/// to instrument code. Call [snapshot], [frameStats], [stabilitySnapshot] to
/// read current data.
final class PerfEngine {
  PerfEngine({required PerfRadarConfig config}) : _config = config;

  final PerfRadarConfig _config;
  final Tracer _tracer = Tracer();

  late final FrameStats _frameStats = FrameStats(
    jankThresholdMicros: _config.jankThresholdMicros,
  );
  late final StabilityRecorder _stability = StabilityRecorder(
    maxErrorsRetained: _config.maxErrorsRetained,
    maxStallsRetained: _config.maxStallsRetained,
    stallThresholdMicros: _config.stallThresholdMicros,
  );
  late final FrameCollector _frameCollector = FrameCollector(
    stats: _frameStats,
  );

  StallWatchdog? _watchdog;

  // Saved previous error handlers so we can chain them.
  FlutterExceptionHandler? _prevFlutterOnError;
  ErrorCallback? _prevPlatformOnError;

  bool _running = false;

  /// Starts the engine: registers frame collector, installs error handlers,
  /// starts the stall watchdog, and records a startup span.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    final startMicros = traceClockNowMicros();

    final binding = WidgetsBinding.instance;
    _frameCollector.start(binding as SchedulerBinding);

    _installErrorHandlers();

    _watchdog = StallWatchdog(
      interval: const Duration(milliseconds: 100),
      threshold: Duration(microseconds: _config.stallThresholdMicros),
      onStall: (durationMicros) {
        _stability.recordStall(durationMicros);
      },
    );

    // Record a startup span once the first frame is drawn.
    binding.addPostFrameCallback((_) {
      final elapsed = traceClockNowMicros() - startMicros;
      _tracer.recorder.record(
        Span(
          spanId: SpanId.generate(),
          parentId: null,
          traceId: SpanId.generate(),
          name: 'startup',
          category: 'perf_radar',
          startMicros: startMicros,
          durationMicros: elapsed,
          status: SpanStatus.ok,
          attributes: const {},
        ),
      );
    });
  }

  void _installErrorHandlers() {
    _prevFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _stability.recordError(
        details.exception,
        details.stack,
        context: 'FlutterError',
      );
      _prevFlutterOnError?.call(details);
    };

    _prevPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _stability.recordError(error, stack, context: 'PlatformDispatcher');
      return _prevPlatformOnError?.call(error, stack) ?? false;
    };
  }

  void _uninstallErrorHandlers() {
    FlutterError.onError = _prevFlutterOnError;
    PlatformDispatcher.instance.onError = _prevPlatformOnError;
    _prevFlutterOnError = null;
    _prevPlatformOnError = null;
  }

  /// Stops the engine and releases all resources.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    final binding = WidgetsBinding.instance;
    _frameCollector.stop(binding as SchedulerBinding);
    _watchdog?.dispose();
    _watchdog = null;
    _uninstallErrorHandlers();
  }

  /// Measures [body] synchronously and records a span.
  T trace<T>(String name, T Function() body, {String? category}) =>
      _tracer.trace(name, body, category: category);

  /// Measures [body] asynchronously and records a span.
  Future<T> traceAsync<T>(
    String name,
    Future<T> Function() body, {
    String? category,
  }) => _tracer.traceAsync(name, body, category: category);

  /// Returns a [SpanHandle] for a manually bounded span.
  SpanHandle startSpan(String name, {String? category}) =>
      _tracer.start(name, category: category);

  /// Immutable snapshot of all span aggregates.
  TraceSnapshot snapshot() => _tracer.snapshot();

  /// Immutable snapshot of frame timing statistics.
  FrameStatsSnapshot get frameStats => _frameStats.snapshot();

  /// Immutable snapshot of stability counters and recent events.
  StabilitySnapshot get stabilitySnapshot => _stability.snapshot();
}
