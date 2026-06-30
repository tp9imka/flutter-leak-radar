import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:radar_trace/radar_trace.dart';

import '../build_mode.dart';
import '../config/perf_radar_config.dart';
import '../engine/perf_engine.dart';
import '../model/frame_stats.dart';
import '../model/stability_snapshot.dart';
import '../safe.dart';
import '../service_extension.dart';
import '../ui/perf_radar_overlay.dart';

/// On-device performance tracer. Static facade; every method is a no-op when
/// disabled or in release builds. Never throws into the host app.
abstract final class PerfRadar {
  static PerfEngine? _engine;

  static final ValueNotifier<PerfRadarConfig> _configNotifier =
      ValueNotifier<PerfRadarConfig>(
        const PerfRadarConfig(enabled: false, stallThresholdMicros: 250000),
      );

  /// Reactive config notifier.
  static ValueListenable<PerfRadarConfig> get configListenable =>
      _configNotifier;

  /// Initialises the perf tracer.
  ///
  /// Call once from `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  /// A no-op when [PerfRadarConfig.enabled] is false or in release builds.
  static Future<void> init(PerfRadarConfig config) async {
    await dispose();
    _configNotifier.value = config;
    if (!kPerfEnabled || !config.enabled) {
      _engine = null;
      return;
    }
    await runSafelyAsync<void>(() async {
      final engine = PerfEngine(config: config);
      await engine.start();
      _engine = engine;
      registerPerfRadarExtension();
    }, fallback: null);
  }

  /// Measures [body] synchronously and records a span.
  ///
  /// Delegates to the running engine when active; otherwise calls [body]
  /// directly. Always returns the body's result. Never throws.
  static T trace<T>(String name, T Function() body, {String? category}) {
    final engine = _engine;
    if (engine == null) return body();
    return engine.trace(name, body, category: category);
  }

  /// Measures [body] asynchronously and records a span.
  static Future<T> traceAsync<T>(
    String name,
    Future<T> Function() body, {
    String? category,
  }) {
    final engine = _engine;
    if (engine == null) return body();
    return engine.traceAsync(name, body, category: category);
  }

  /// Returns a [SpanHandle] for a manually bounded span.
  ///
  /// When no engine is active, returns an inert no-op handle.
  static SpanHandle start(String name, {String? category}) {
    final engine = _engine;
    if (engine != null) return engine.startSpan(name, category: category);
    return _inertSpanHandle();
  }

  /// Returns an immutable snapshot of all span aggregates.
  static TraceSnapshot snapshot() {
    final engine = _engine;
    if (engine != null) return engine.snapshot();
    return TraceSnapshot(stats: const {}, totalDropCount: 0);
  }

  /// Returns a snapshot of frame timing statistics.
  static FrameStatsSnapshot get frameStats {
    final engine = _engine;
    if (engine != null) return engine.frameStats;
    return const FrameStatsSnapshot(frameCount: 0, jankCount: 0);
  }

  /// Returns a snapshot of stability counters and recent events.
  static StabilitySnapshot get stabilitySnapshot {
    final engine = _engine;
    if (engine != null) return engine.stabilitySnapshot;
    return const StabilitySnapshot(
      errorCount: 0,
      stallCount: 0,
      recentErrors: [],
      recentStalls: [],
    );
  }

  /// Wraps [child] with a [PerfRadarOverlay] when the engine is active and
  /// [PerfRadarConfig.showOverlay] is true.
  static Widget overlay({required Widget child}) {
    final config = _configNotifier.value;
    if (!kPerfEnabled || _engine == null || !config.showOverlay) return child;
    return runSafely(() => PerfRadarOverlay(child: child), fallback: child);
  }

  /// Stops the engine and releases all resources.
  static Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _configNotifier.value = const PerfRadarConfig(
      enabled: false,
      stallThresholdMicros: 250000,
    );
    if (engine != null) {
      await runSafelyAsync(() => engine.stop(), fallback: null);
    }
  }
}

/// Creates an inert [SpanHandle] that records nothing.
///
/// [SpanHandle] is final and cannot be subclassed outside its library, so we
/// construct one directly with a disabled [TraceRecorder].
SpanHandle _inertSpanHandle() {
  final spanId = SpanId.generate();
  return SpanHandle(
    pendingSpan: Span(
      spanId: spanId,
      parentId: null,
      traceId: spanId,
      name: '_inert',
      category: null,
      startMicros: 0,
      durationMicros: 0,
      status: SpanStatus.ok,
      attributes: const {},
    ),
    recorder: TraceRecorder(enabled: false),
  );
}
