// lib/src/engine/leak_engine.dart
import 'dart:async';

import 'package:meta/meta.dart';

import '../analysis/leak_analyzer.dart';
import '../analysis/sample_history.dart';
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../precise/leak_object_registry.dart';
import '../util/rate_limited_logger.dart';
import '../util/safe.dart';
import 'class_sample.dart';
import 'heap_probe.dart';

/// Orchestrates capture → analyze → report. Internal; reachable from the
/// facade and tests, but never part of the public API.
@internal
class LeakEngine {
  LeakEngine({
    required HeapProbe probe,
    required LeakAnalyzer analyzer,
    SampleHistory? history,
    LeakObjectRegistry? registry,
    int gcCyclesForPreciseLeak = 3,
    RateLimitedLogger? logger,
  })  : _probe = probe,
        _analyzer = analyzer,
        _history = history ?? SampleHistory(),
        _registry = registry ?? LeakObjectRegistry(),
        _gcCyclesForPreciseLeak = gcCyclesForPreciseLeak,
        _logger = logger ?? RateLimitedLogger();

  final HeapProbe _probe;
  final LeakAnalyzer _analyzer;
  final SampleHistory _history;
  final LeakObjectRegistry _registry;
  final int _gcCyclesForPreciseLeak;
  final RateLimitedLogger _logger;

  final StreamController<LeakReport> _reports =
      StreamController<LeakReport>.broadcast();
  LeakRadarStatus _status = LeakRadarStatus.disabled;
  LeakReport? _latest;
  bool _scanning = false;

  /// Broadcast stream of every scan result.
  Stream<LeakReport> get reports => _reports.stream;

  /// The most recent scan result, or null if no scan has completed yet.
  LeakReport? get latest => _latest;

  /// Current operational status of the engine.
  LeakRadarStatus get status => _status;

  /// Initialises the engine by checking probe availability and setting status.
  Future<void> start() async {
    final available = await runSafelyAsync<bool>(
      () => _probe.isAvailable,
      fallback: false,
      logger: _logger,
    );
    _status =
        available ? LeakRadarStatus.active : LeakRadarStatus.preciseOnly;
  }

  /// Registers [o] for precise leak tracking under the given [tag].
  void track(Object o, {required String tag}) =>
      _registry.track(o, tag: tag);

  /// Records that [o] has been disposed. Pairs with [track].
  void markDisposed(Object o) => _registry.markDisposed(o);

  /// Captures a heap snapshot (when active), analyses history, and returns a
  /// [LeakReport]. Overlapping calls are dropped — the in-flight scan's result
  /// is returned instead of queuing a second capture.
  Future<LeakReport> scan({String trigger = 'manual'}) async {
    if (_status == LeakRadarStatus.disabled) return _degraded(trigger);
    if (_scanning) return _latest ?? _degraded(trigger);
    _scanning = true;
    try {
      if (_status == LeakRadarStatus.active) {
        final snapshot = await runSafelyAsync<HeapSnapshot?>(
          () => _probe.capture(forceGc: true),
          fallback: null,
          logger: _logger,
        );
        if (snapshot == null) {
          _status = LeakRadarStatus.serviceUnavailable;
        } else {
          _history.add(snapshot);
        }
      }
      final precise = _registry.collectLeaks(
        gcCycles: _gcCyclesForPreciseLeak,
      );
      final report = _analyzer.analyze(
        _history,
        trigger: trigger,
        status: _status,
        preciseFindings: precise,
      );
      _latest = report;
      if (!_reports.isClosed) _reports.add(report);
      return report;
    } finally {
      _scanning = false;
    }
  }

  LeakReport _degraded(String trigger) => LeakReport(
        findings: const <LeakFinding>[],
        capturedAt: DateTime.now(),
        trigger: trigger,
        status: _status,
      );

  /// Disposes the probe, clears tracking state, and closes the reports stream.
  Future<void> stop() async {
    await runSafelyAsync<void>(
      () => _probe.dispose(),
      fallback: null,
      logger: _logger,
    );
    _registry.clear();
    await _reports.close();
    _status = LeakRadarStatus.disabled;
  }
}
