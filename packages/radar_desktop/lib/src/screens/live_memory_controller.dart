import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:radar_trace/radar_trace.dart';

import '../seams/desktop_memory_poll.dart';

/// Accumulates live Dart-heap and external memory readings from a connected
/// app into two gap-aware [MetricSeries] — the connected-mode counterpart to
/// the import-first Device Monitor.
///
/// Each [pollOnce] appends one sample per series on success, or opens a
/// measurement gap on failure. Heap and external are kept as TWO separate
/// series and never merged: they apply GC pressure differently and a reader
/// must be able to tell an external-memory ramp from a Dart-heap ramp.
///
/// Poll cadence is driven either manually (call [pollOnce]) or on a periodic
/// [Timer] between [start] and [stop]. Inject [poll] and [clock] in tests to
/// avoid real VM wiring and wall-clock nondeterminism.
class LiveMemoryController extends ChangeNotifier {
  /// Creates a controller polling through [poll].
  ///
  /// [clock] returns host wall-clock microseconds (defaults to
  /// [DateTime.now]); [interval] is the periodic cadence used by [start];
  /// [maxSamples] caps the rolling window (defaults to [maxRetainedSamples]).
  LiveMemoryController({
    required MemoryPoll poll,
    int Function()? clock,
    this.interval = const Duration(seconds: 1),
    int maxSamples = maxRetainedSamples,
  }) : _poll = poll,
       _clock = clock ?? _wallClockMicros,
       _maxSamples = maxSamples;

  /// The metric name of the Dart-heap-usage series.
  static const String heapSeriesName = 'dart.heap.used';

  /// The metric name of the external-memory series.
  static const String externalSeriesName = 'dart.external';

  /// Default rolling-window cap: ~4 hours of samples at the default 1s
  /// cadence. A live view is a bounded window, not an unbounded buffer, so a
  /// long-running session can never grow memory without limit.
  static const int maxRetainedSamples = 4 * 60 * 60;

  final MemoryPoll _poll;
  final int Function() _clock;
  final int _maxSamples;

  /// Cadence used by [start]'s periodic timer.
  final Duration interval;

  final List<MetricSample> _heap = [];
  final List<MetricSample> _external = [];
  List<SeriesGap> _gaps = const [];

  int? _lastSampleMicros;
  int? _gapOpenMicros;
  String? _lastError;
  Timer? _timer;

  /// The accumulated Dart-heap-usage series (bytes), gap-aware.
  MetricSeries get heapSeries => MetricSeries(
    name: heapSeriesName,
    unit: 'bytes',
    samples: List.unmodifiable(_heap),
    gaps: _gaps,
  );

  /// The accumulated external-memory series (bytes), gap-aware. Carries the
  /// SAME gaps as [heapSeries] — a failed RPC breaks both lines identically.
  MetricSeries get externalSeries => MetricSeries(
    name: externalSeriesName,
    unit: 'bytes',
    samples: List.unmodifiable(_external),
    gaps: _gaps,
  );

  /// Number of successful samples collected so far.
  int get sampleCount => _heap.length;

  /// The most recent poll failure message, or null after a success.
  String? get lastError => _lastError;

  /// Whether a periodic poll timer is currently running.
  bool get isPolling => _timer != null;

  /// Starts polling on a periodic [interval] timer. A no-op if already
  /// polling. Does not poll immediately — the first tick fires after
  /// [interval]; call [pollOnce] first for an immediate reading.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(pollOnce()));
    notifyListeners();
  }

  /// Stops the periodic poll timer. Safe to call when not polling.
  void stop() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    notifyListeners();
  }

  /// Performs a single poll: appends a sample on success (closing any open
  /// gap first), or opens a measurement gap on failure. Never throws.
  Future<void> pollOnce() async {
    final now = _clock();
    try {
      final sample = await _poll();
      final openedAt = _gapOpenMicros;
      if (openedAt != null) {
        _gaps = [
          ..._gaps,
          SeriesGap(
            startMicros: openedAt,
            endMicros: now,
            reason: _lastError ?? 'RPC failure',
          ),
        ];
        _gapOpenMicros = null;
      }
      _heap.add(MetricSample(tMicros: now, value: sample.heapUsage.toDouble()));
      _external.add(
        MetricSample(tMicros: now, value: sample.externalUsage.toDouble()),
      );
      _lastSampleMicros = now;
      _lastError = null;
      _trim();
    } catch (error) {
      // A failed poll records no sample. Open a gap from the last good sample
      // (or this poll's time when none yet) so the line breaks honestly rather
      // than bridging across the not-measured interval.
      _gapOpenMicros ??= _lastSampleMicros ?? now;
      _lastError = error.toString();
    }
    notifyListeners();
  }

  /// Enforces the rolling-window cap: drops the oldest samples (identically in
  /// both series) and any gap that no longer reaches into the retained window.
  /// A gap whose end is at or before the earliest retained sample can break no
  /// remaining line, so it is dropped rather than left dangling.
  void _trim() {
    if (_heap.length <= _maxSamples) return;
    final removeCount = _heap.length - _maxSamples;
    _heap.removeRange(0, removeCount);
    _external.removeRange(0, removeCount);
    if (_gaps.isEmpty) return;
    final firstMicros = _heap.first.tMicros;
    _gaps = [
      for (final gap in _gaps)
        if (gap.endMicros > firstMicros) gap,
    ];
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  static int _wallClockMicros() => DateTime.now().microsecondsSinceEpoch;
}
