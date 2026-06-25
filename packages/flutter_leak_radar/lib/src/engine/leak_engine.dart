// lib/src/engine/leak_engine.dart
import 'dart:async';

import 'package:leak_graph/leak_graph.dart';
import 'package:meta/meta.dart';

import '../analysis/leak_analyzer.dart';
import '../analysis/sample_history.dart';
import '../config/leak_radar_config.dart';
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../model/retaining_path.dart';
import '../precise/force_gc.dart';
import '../precise/leak_object_registry.dart';
import '../triggers/navigator_observer.dart';
import '../triggers/scan_scheduler.dart';
import '../util/rate_limited_logger.dart';
import '../util/safe.dart';
import 'class_sample.dart';
import 'graph_finding_mapper.dart';
import 'graph_scan_runner.dart';
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
    GraphScanRunner? graphRunner,
    Future<void> Function()? gcForcer,
  }) : _probe = probe,
       _analyzer = analyzer,
       _history = history ?? SampleHistory(),
       _registry = registry ?? LeakObjectRegistry(),
       _gcCyclesForPreciseLeak = gcCyclesForPreciseLeak,
       _logger = logger ?? RateLimitedLogger(),
       _autoScan = autoScan ?? config?.autoScan ?? const AutoScan(),
       _config = config ?? const LeakRadarConfig(),
       _graphRunner = graphRunner ?? IsolateGraphScanRunner(logger: logger),
       _gcForcer =
           gcForcer ?? (() => forceGc(timeout: const Duration(seconds: 4)));

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

  /// Acquires + analyses a heap snapshot OFF the main isolate. Injectable for
  /// tests; defaults to [IsolateGraphScanRunner].
  final GraphScanRunner _graphRunner;
  int _navCount = 0;
  bool _graphScanInFlight = false;

  /// When the last navigation-triggered graph scan ran. A min-interval cooldown
  /// keyed off this neutralises bursty push/pop (which `_graphScanInFlight` does
  /// not — it only blocks overlap, not back-to-back sequential scans).
  DateTime? _lastGraphScanAt;
  static const Duration _graphScanCooldown = Duration(seconds: 30);

  /// Forces a real GC so the precise tracker's reachability barrier advances
  /// and pending finalizers run. Injectable for tests; defaults to [forceGc].
  final Future<void> Function() _gcForcer;

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
    final gs = _config.graphScan;
    final graphScanDesc = gs == null
        ? 'off'
        : 'every ${gs.everyNthNavigation} nav,minCluster=${gs.minClusterSize},'
              'appPackages=${gs.appPackages}';
    _logger.log(
      'engine.start: isAvailable=$available status=$_status '
      'preciseTracking=${_config.preciseTracking} '
      'autoScan=${_autoScan.hasPeriodic ? 'periodic ${_autoScan.period}' : ''}'
      '${_autoScan.onNavigation ? '+nav' : ''} '
      'graphScan=$graphScanDesc rules=${_config.rules.length}',
      level: LeakLogLevel.verbose,
    );
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
        onScan: () =>
            runSafelyAsync(() => _navScan(), fallback: null, logger: _logger),
        debounce: _autoScan.navigationDebounce,
      );
    }
  }

  Future<LeakReport> _navScan() async {
    final report = await scan(trigger: 'navigation');
    _navCount++;
    final gs = _config.graphScan;
    final everyNth = gs?.everyNthNavigation ?? 0;
    final triggers = gs != null && _navCount % gs.everyNthNavigation == 0;
    if (gs == null) {
      _logger.log(
        'navScan: navCount=$_navCount; graphScan off',
        level: LeakLogLevel.verbose,
      );
    } else if (triggers) {
      _logger.log(
        'navScan: navCount=$_navCount; graphScan TRIGGERS this nav '
        '(everyNth=$everyNth)',
        level: LeakLogLevel.verbose,
      );
    } else {
      final next = (_navCount ~/ everyNth + 1) * everyNth;
      _logger.log(
        'navScan: navCount=$_navCount; graphScan skipped (next at $next)',
        level: LeakLogLevel.verbose,
      );
    }
    if (triggers) {
      final now = DateTime.now();
      final since = _lastGraphScanAt == null
          ? null
          : now.difference(_lastGraphScanAt!);
      if (since != null && since < _graphScanCooldown) {
        _logger.log(
          'navScan: graphScan skipped (cooldown, last ${since.inSeconds}s ago)',
          level: LeakLogLevel.verbose,
        );
      } else {
        _lastGraphScanAt = now;
        await _runGraphScan(report);
      }
    }
    return _latestFiltered ?? report;
  }

  Future<void> _runGraphScan(LeakReport baseReport) async {
    if (_graphScanInFlight) return;
    final gs = _config.graphScan;
    if (gs == null) return;
    // Pre-write size gate. When the VM service is connected the latest capture
    // already gives the live-object total, so skip the ENTIRE snapshot pipeline
    // (write + read + parse + node cache) for a heap too large to analyse
    // in-app. This is what stops the per-scan native OOM on a bloated heap —
    // the runner's own guard only fires after the heap is already in memory.
    final total = _history.latestObjectTotal;
    if (total != null && total > gs.maxGraphObjects) {
      _logger.log(
        'graphScan: skipped pre-write (total=$total > '
        'maxGraphObjects=${gs.maxGraphObjects})',
        level: LeakLogLevel.verbose,
      );
      return;
    }
    _graphScanInFlight = true;
    try {
      await runSafelyAsync<void>(
        () async {
          _logger.log(
            'graphScan: capturing snapshot + analysing in a background isolate '
            '(maxObjects=${gs.maxGraphObjects})',
            level: LeakLogLevel.verbose,
          );
          final result = await _graphRunner.run(
            GraphAnalysisOptions(
              confirmWithReachability: true,
              appPackages: gs.appPackages,
              minClusterSize: gs.minClusterSize,
            ),
            maxObjects: gs.maxGraphObjects,
          );
          if (result == null) {
            _logger.log(
              'graphScan: no result (snapshot unsupported, too large, or '
              'analysis failed) -> NO graph findings',
              level: LeakLogLevel.verbose,
            );
            return;
          }
          final stats = result.stats;
          _logger.log(
            'graphScan analyze: stats{totalObjects=${stats.totalObjects},'
            'reachable=${stats.reachableObjects},'
            'leakCandidates=${stats.leakCandidates},'
            'suppressedByAppFilter=${stats.suppressedByAppFilter},'
            'suppressedByLiveTree=${stats.suppressedByLiveTree},'
            'clusters=${stats.clusters},'
            'warnings=${stats.warnings.length}}; '
            'minClusterSize=${gs.minClusterSize}',
            level: LeakLogLevel.verbose,
          );
          if (result.clusters.isEmpty) {
            _logger.log(
              'graphScan result: rawClusters=0 -> mappedFindings=0 '
              '(NO retainedByNonLiveRoot produced)',
              level: LeakLogLevel.verbose,
            );
            return;
          }
          final graphFindings = result.clusters.map(mapGraphCluster).toList();
          _logger.log(
            'graphScan result: rawClusters=${result.clusters.length} -> '
            'mappedFindings=${graphFindings.length} '
            '(retainedByNonLiveRoot added)',
            level: LeakLogLevel.verbose,
          );
          final merged = LeakReport(
            findings: [...baseReport.findings, ...graphFindings],
            capturedAt: baseReport.capturedAt,
            trigger: baseReport.trigger,
            status: baseReport.status,
            heapBytes: baseReport.heapBytes,
          );
          _latestFullReport = merged;
          final filtered = _filtered(merged);
          _latestFiltered = filtered;
          if (!_reports.isClosed) _reports.add(filtered);
        },
        fallback: null,
        logger: _logger,
      );
    } finally {
      _graphScanInFlight = false;
    }
  }

  /// Runs a one-shot graph scan and merges findings into the latest report.
  ///
  /// No-op when [LeakRadarConfig.graphScan] is null. Never throws.
  Future<void> graphScanNow() async {
    if (_config.graphScan == null) return;
    final base = _latestFullReport ?? _degraded('graph_manual');
    await runSafelyAsync<void>(
      () => _runGraphScan(base),
      fallback: null,
      logger: _logger,
    );
  }

  /// Forces a GC — advancing the precise tracker's reachability barrier and
  /// running pending finalizers — then runs a full scan. Surfaces
  /// notGced / notDisposed leaks on demand instead of waiting for an
  /// incidental GC. Never throws.
  Future<LeakReport> forceGcAndScan() async {
    await runSafelyAsync<void>(
      () => _gcForcer(),
      fallback: null,
      logger: _logger,
    );
    return scan(trigger: 'force_gc');
  }

  /// The config the engine is actually running with. Internal: read by the
  /// facade's test seam to assert [LeakRadar.init] forwards the full config.
  @internal
  LeakRadarConfig get debugConfig => _config;

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
          _logger.log(
            'scan[$trigger]: capture -> NULL snapshot '
            '(VM unreachable, history NOT advanced); historySize=${_history.length}',
            level: LeakLogLevel.verbose,
          );
        } else {
          _history.add(snapshot);
          _logger.log(
            'scan[$trigger]: capture -> ${snapshot.samples.length} class samples; '
            'historySize=${_history.length}',
            level: LeakLogLevel.verbose,
          );
        }
      }
      // Force a real GC so the precise tracker's reachability barrier advances
      // (and pending finalizers run) before we read it. Without this, a
      // service-triggered GC does not reliably advance developer.reachabilityBarrier,
      // so disposed-but-retained objects never reach the gcCycles threshold.
      // Gated on having tracked objects to avoid needless GC pressure.
      final trackedBefore = _registry.trackedCount;
      final gcInvoked = _config.preciseTracking && trackedBefore > 0;
      if (gcInvoked) {
        await runSafelyAsync<void>(
          () => _gcForcer(),
          fallback: null,
          logger: _logger,
        );
      }
      final precise = _registry.collectLeaks(gcCycles: _gcCyclesForPreciseLeak);
      final notGced = precise.where((f) => f.kind == LeakKind.notGced).length;
      final notDisposed = precise
          .where((f) => f.kind == LeakKind.notDisposed)
          .length;
      _logger.log(
        'scan[$trigger]: forceGc invoked=$gcInvoked (tracked=$trackedBefore); '
        'precise=${precise.length} {notGced=$notGced, notDisposed=$notDisposed}',
        level: LeakLogLevel.verbose,
      );
      final report = _analyzer.analyze(
        _history,
        trigger: trigger,
        status: _status,
        preciseFindings: precise,
      );
      _latestFullReport = report;
      final filtered = _filtered(report);
      _latestFiltered = filtered;
      _logger.log(
        'scan[$trigger] done: full=${report.findings.length} '
        'by kind=${_countByKind(report.findings)} -> '
        'afterThreshold(${_config.reportThreshold.name})=${filtered.findings.length}; '
        'status=$_status',
        level: LeakLogLevel.verbose,
      );
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

  /// Renders a `kind->count` map string for verbose scan diagnostics.
  String _countByKind(List<LeakFinding> findings) {
    final counts = <LeakKind, int>{};
    for (final f in findings) {
      counts[f.kind] = (counts[f.kind] ?? 0) + 1;
    }
    return '{${counts.entries.map((e) => '${e.key.name}:${e.value}').join(',')}}';
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
