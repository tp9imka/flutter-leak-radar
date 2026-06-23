// lib/src/leak_radar.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'analysis/leak_analyzer.dart';
import 'analysis/sample_history.dart';
import 'config/leak_radar_config.dart';
import 'engine/heap_probe.dart';
import 'engine/leak_engine.dart';
import 'engine/vm_heap_probe.dart';
import 'model/leak_kind.dart';
import 'model/leak_report.dart';
import 'model/retaining_path.dart';
import 'precise/leak_object_registry.dart';
import 'ui/leak_radar_overlay.dart';
import 'util/build_mode.dart';
import 'util/rate_limited_logger.dart';
import 'util/safe.dart';

/// Output format for [LeakRadar.exportToFile].
enum LeakExportFormat { json, markdown }

/// An inert [NavigatorObserver] used when the engine is disabled or in release.
///
/// All navigation callbacks are no-ops; instances are safe to add to
/// [MaterialApp.navigatorObservers] without any side effects.
class _InertNavigatorObserver extends NavigatorObserver {}

/// On-device leak detector. Static facade; every method is a no-op in release
/// or when disabled, and never throws into the host.
abstract final class LeakRadar {
  static LeakEngine? _engine;
  static RateLimitedLogger _logger = RateLimitedLogger();
  static final NavigatorObserver _inertObserver = _InertNavigatorObserver();
  static bool _showOverlay = true;

  static Future<void> init(LeakRadarConfig config) async {
    await dispose();
    if (!kEngineEnabled || !config.enabled) {
      _engine = null;
      return;
    }
    await runSafelyAsync<void>(() async {
      _logger = RateLimitedLogger(level: config.logLevel);
      HeapProbe probe = VmHeapProbe(
        logger: _logger,
        maxRetainingPathRequests: config.maxRetainingPathRequests,
      );
      if (!await probe.isAvailable) {
        await probe.dispose();
        probe = const NoopHeapProbe();
      }
      final engine = LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(config.suspects.merge(config.rules)),
        history: SampleHistory(maxSnapshots: config.maxSnapshots),
        registry: LeakObjectRegistry(disposalGrace: config.disposalGrace),
        gcCyclesForPreciseLeak: config.gcCyclesForPreciseLeak,
        logger: _logger,
        autoScan: config.autoScan,
      );
      await engine.start();
      _showOverlay = config.showOverlay;
      _engine = engine;
    }, fallback: null, logger: _logger);
  }

  /// Test seam: install a pre-built engine (e.g. with a FakeHeapProbe).
  @visibleForTesting
  static Future<void> debugInstall(LeakEngine engine) async {
    await dispose();
    await engine.start();
    _engine = engine;
  }

  static Future<LeakReport> scan({String trigger = 'manual'}) {
    final capturedAt = DateTime.now();
    final engine = _engine;
    if (engine == null) {
      return Future.value(LeakReport(
        findings: const [],
        capturedAt: capturedAt,
        trigger: trigger,
        status: LeakRadarStatus.disabled,
      ));
    }
    return runSafelyAsync(
      () => engine.scan(trigger: trigger),
      fallback: LeakReport(
        findings: const [],
        capturedAt: capturedAt,
        trigger: trigger,
        status: LeakRadarStatus.serviceUnavailable,
      ),
      logger: _logger,
    );
  }

  static void track(Object object, {required String tag}) =>
      runSafely<void>(() => _engine?.track(object, tag: tag), fallback: null, logger: _logger);

  static void markDisposed(Object object) =>
      runSafely<void>(() => _engine?.markDisposed(object), fallback: null, logger: _logger);

  static Stream<LeakReport> get reports =>
      runSafely(() => _engine?.reports ?? const Stream<LeakReport>.empty(), fallback: const Stream<LeakReport>.empty(), logger: _logger);

  static LeakReport? get latest =>
      runSafely(() => _engine?.latest, fallback: null, logger: _logger);

  static LeakRadarStatus get status =>
      runSafely(() => _engine?.status ?? LeakRadarStatus.disabled, fallback: LeakRadarStatus.disabled, logger: _logger);

  /// Returns the [NavigatorObserver] wired to navigation-triggered scans when
  /// the engine is active and [AutoScan.onNavigation] is true. Falls back to
  /// an inert no-op observer when disabled, in release builds, or on error —
  /// so callers can unconditionally add this to [MaterialApp.navigatorObservers]
  /// without guarding against null.
  static NavigatorObserver get navigatorObserver =>
      runSafely(
        () => _engine?.navigatorObserver ?? _inertObserver,
        fallback: _inertObserver,
        logger: _logger,
      );

  /// Wraps [child] with a [LeakRadarOverlay] when the engine is active and
  /// [LeakRadarConfig.showOverlay] is true. Returns [child] unchanged when the
  /// engine is disabled, in release, or [showOverlay] is false.
  ///
  /// Any internal error is swallowed — [child] is returned as the fallback so
  /// the host app is never affected.
  static Widget overlay({required Widget child}) {
    if (!kEngineEnabled || _engine == null || !_showOverlay) return child;
    return runSafely(
      () => LeakRadarOverlay(show: true, child: child),
      fallback: child,
      logger: _logger,
    );
  }

  /// Lazily fetches the retaining path for [className] from the active engine.
  ///
  /// Returns null when the engine is absent, the probe does not support
  /// retaining paths, or any error occurs — never throws into the host.
  /// Called by the UI layer only on explicit user expand; never during a scan.
  @internal
  static Future<RetainingPathView?> fetchRetainingPath(
    String className,
  ) =>
      runSafelyAsync(
        () =>
            _engine?.retainingPath(className) ??
            Future<RetainingPathView?>.value(null),
        fallback: null,
        logger: _logger,
      );

  /// Writes the latest scan report to a file and returns the absolute path.
  ///
  /// Returns `null` when:
  /// - the engine is disabled / not initialised (no report available),
  /// - no scan has been performed yet,
  /// - any I/O error occurs (always swallowed — never throws into the host).
  ///
  /// [format] selects between JSON (`leak_report_<ts>.json`) and Markdown
  /// (`leak_report_<ts>.md`). [directory] overrides the destination directory;
  /// it defaults to [Directory.systemTemp] when omitted.
  static Future<String?> exportToFile({
    LeakExportFormat format = LeakExportFormat.markdown,
    Directory? directory,
  }) =>
      runSafelyAsync<String?>(() async {
        final report = _engine?.latest;
        if (report == null) return null;

        final dir = directory ?? Directory.systemTemp;
        final stamp = report.capturedAt.millisecondsSinceEpoch;
        final ext = format == LeakExportFormat.json ? 'json' : 'md';
        final file = File('${dir.path}/leak_report_$stamp.$ext');

        final content = format == LeakExportFormat.json
            ? jsonEncode(report.toJson())
            : report.toMarkdown();
        await file.writeAsString(content);
        return file.path;
      }, fallback: null, logger: _logger);

  static Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await runSafelyAsync(() => engine.stop(), fallback: null, logger: _logger);
    }
  }
}
