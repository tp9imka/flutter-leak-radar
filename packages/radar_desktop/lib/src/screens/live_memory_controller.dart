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
  /// [DateTime.now]); [interval] is the periodic cadence used by [start].
  LiveMemoryController({
    required MemoryPoll poll,
    int Function()? clock,
    this.interval = const Duration(seconds: 1),
  }) : _poll = poll,
       _clock = clock ?? _wallClockMicros;

  /// The metric name of the Dart-heap-usage series.
  static const String heapSeriesName = 'dart.heap.used';

  /// The metric name of the external-memory series.
  static const String externalSeriesName = 'dart.external';

  final MemoryPoll _poll;
  final int Function() _clock;

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
    } catch (error) {
      // A failed poll records no sample. Open a gap from the last good sample
      // (or this poll's time when none yet) so the line breaks honestly rather
      // than bridging across the not-measured interval.
      _gapOpenMicros ??= _lastSampleMicros ?? now;
      _lastError = error.toString();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  static int _wallClockMicros() => DateTime.now().microsecondsSinceEpoch;
}
