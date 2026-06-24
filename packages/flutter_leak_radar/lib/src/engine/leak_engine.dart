// lib/src/engine/leak_engine.dart
import 'dart:async';

import 'package:meta/meta.dart';

import '../analysis/leak_analyzer.dart';
import '../analysis/sample_history.dart';
import '../config/leak_radar_config.dart';
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../model/retaining_path.dart';
import '../precise/leak_object_registry.dart';
import '../triggers/navigator_observer.dart';
import '../triggers/scan_scheduler.dart';
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
    AutoScan? autoScan,
    LeakRadarConfig? config,
  }) : _probe = probe,
       _analyzer = analyzer,
       _history = history ?? SampleHistory(),
       _registry = registry ?? LeakObjectRegistry(),
       _gcCyclesForPreciseLeak = gcCyclesForPreciseLeak,
       _logger = logger ?? RateLimitedLogger(),
       _autoScan = autoScan ?? config?.autoScan ?? const AutoScan(),
       _config = config ?? const LeakRadarConfig();

  final HeapProbe _probe;
  final LeakAnalyzer _analyzer;
  final SampleHistory _history;
  final LeakObjectRegistry _registry;
  final int _gcCyclesForPreciseLeak;
  final RateLimitedLogger _logger;
  AutoScan _autoScan;
  LeakRadarConfig _config;
  ScanScheduler? _scheduler;
  LeakRadarNavigatorObserver? _navObserver;

  final StreamController<LeakReport> _reports =
      StreamController<LeakReport>.broadcast();
  LeakRadarStatus _status = LeakRadarStatus.disabled;

  /// Full unfiltered report kept so re-filtering on threshold change is cheap.
  LeakReport? _latestFullReport;

  /// Filtered report matching the current [LeakRadarConfig.reportThreshold].
  LeakReport? _latestFiltered;
  bool _scanning = false;

  /// Broadcast stream of every scan result.
  Stream<LeakReport> get reports => _reports.stream;

  /// The most recent scan result filtered by [LeakRadarConfig.reportThreshold],
  /// or null if no scan has completed yet.
  LeakReport? get latest => _latestFiltered;

  /// Current operational status of the engine.
  LeakRadarStatus get status => _status;

  /// The navigator observer wired to [scan] with trigger `'navigation'`, or
  /// `null` when [AutoScan.onNavigation] is false.
  LeakRadarNavigatorObserver? get navigatorObserver => _navObserver;

  /// Initialises the engine by checking probe availability and setting status.
  Future<void> start() async {
    final available = await runSafelyAsync<bool>(
      () => _probe.isAvailable,
      fallback: false,
      logger: _logger,
    );
    _status = available ? LeakRadarStatus.active : LeakRadarStatus.preciseOnly;
    _startAutoScan();
  }

  /// Updates the running config. Reconfigures auto-scan triggers if needed.
  ///
  /// All mutations are safe — never throws. When [LeakRadarConfig.autoScan]
  /// changes, the old scheduler and nav observer are stopped and recreated.
  /// When [LeakRadarConfig.preciseTracking] changes to false, the registry
  /// is cleared. When [LeakRadarConfig.reportThreshold] changes, the last
  /// full report is re-filtered and re-emitted on the [reports] stream.
  void updateConfig(LeakRadarConfig newConfig) {
    runSafely<void>(
      () {
        final autoScanChanged = newConfig.autoScan != _config.autoScan;
        final preciseTrackingDisabled =
            _config.preciseTracking && !newConfig.preciseTracking;

        // Keep _autoScan in sync before restarting the scheduler, so
        // _startAutoScan always sees the new period / flags regardless of whether
        // the engine is currently disabled.
        _autoScan = newConfig.autoScan;

        if (autoScanChanged && _status != LeakRadarStatus.disabled) {
          _scheduler?.stop();
          _scheduler = null;
          _navObserver?.dispose();
          _navObserver = null;
          _startAutoScan();
        }

        if (preciseTrackingDisabled) _registry.clear();

        _config = newConfig;

        // Re-filter and re-emit whenever the threshold or the config changes
        // so listeners always see a report consistent with the current config.
        if (_latestFullReport != null && !_reports.isClosed) {
          _latestFiltered = _filtered(_latestFullReport!);
          _reports.add(_latestFiltered!);
        }
      },
      fallback: null,
      logger: _logger,
    );
  }

  void _startAutoScan() {
    if (_autoScan.hasPeriodic) {
      _scheduler = ScanScheduler(
        period: _autoScan.period,
        onTick: () => runSafelyAsync<LeakReport?>(
          () => scan(trigger: 'periodic'),
          fallback: null,
          logger: _logger,
        ),
      );
      _scheduler!.start();
    }
    if (_autoScan.onNavigation) {
      _navObserver = LeakRadarNavigatorObserver(
        onScan: () => runSafelyAsync(
          () => scan(trigger: 'navigation'),
          fallback: null,
          logger: _logger,
        ),
        debounce: _autoScan.navigationDebounce,
      );
    }
  }

  /// Registers [o] for precise leak tracking under the given [tag].
  ///
  /// No-op when [LeakRadarConfig.preciseTracking] is false.
  void track(Object o, {required String tag}) {
    if (!_config.preciseTracking) return;
    _registry.track(o, tag: tag);
  }

  /// Records that [o] has been disposed. Pairs with [track].
  ///
  /// No-op when [LeakRadarConfig.preciseTracking] is false.
  void markDisposed(Object o) {
    if (!_config.preciseTracking) return;
    _registry.markDisposed(o);
  }

  /// Captures a heap snapshot (when active), analyses history, and returns a
  /// [LeakReport]. Overlapping calls are dropped — the in-flight scan's result
  /// is returned instead of queuing a second capture.
  Future<LeakReport> scan({String trigger = 'manual'}) async {
    if (_status == LeakRadarStatus.disabled) return _degraded(trigger);
    if (_scanning) return _latestFiltered ?? _degraded(trigger);
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
      final precise = _registry.collectLeaks(gcCycles: _gcCyclesForPreciseLeak);
      final report = _analyzer.analyze(
        _history,
        trigger: trigger,
        status: _status,
        preciseFindings: precise,
      );
      _latestFullReport = report;
      final filtered = _filtered(report);
      _latestFiltered = filtered;
      if (!_reports.isClosed) _reports.add(filtered);
      return filtered;
    } finally {
      _scanning = false;
    }
  }

  /// Resets all accumulated leak state without stopping the engine.
  ///
  /// Clears the precise registry, empties the snapshot history, sets both the
  /// full and filtered latest reports to an empty report, and emits the empty
  /// report on [reports] so the UI updates immediately.
  void clearLeaks() {
    _registry.clear();
    _history.clear();
    final empty = _degraded('clear');
    _latestFullReport = empty;
    _latestFiltered = empty;
    if (!_reports.isClosed) _reports.add(empty);
  }

  /// Returns a copy of [full] with findings below [LeakRadarConfig.reportThreshold]
  /// removed.
  LeakReport _filtered(LeakReport full) => LeakReport(
    findings: full.findings
        .where((f) => f.severity.index >= _config.reportThreshold.index)
        .toList(),
    capturedAt: full.capturedAt,
    trigger: full.trigger,
    status: full.status,
    heapBytes: full.heapBytes,
  );

  LeakReport _degraded(String trigger) => LeakReport(
    findings: const <LeakFinding>[],
    capturedAt: DateTime.now(),
    trigger: trigger,
    status: _status,
  );

  /// Fetches the retaining path for [className] from the underlying probe.
  ///
  /// Returns null when the probe does not support retaining paths or when the
  /// engine is unavailable. Never throws.
  Future<RetainingPathView?> retainingPath(String className) => runSafelyAsync(
    () => _probe.retainingPath(className),
    fallback: null,
    logger: _logger,
  );

  /// Disposes the probe, clears tracking state, and closes the reports stream.
  Future<void> stop() async {
    _scheduler?.stop();
    _scheduler = null;
    _navObserver?.dispose();
    _navObserver = null;
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
