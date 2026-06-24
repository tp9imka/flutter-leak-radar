// lib/src/leak_radar.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'analysis/leak_analyzer.dart';
import 'analysis/sample_history.dart';
import 'config/leak_radar_config.dart';
import 'engine/heap_probe.dart';
import 'engine/heap_snapshot_file.dart';
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
enum LeakExportFormat {
  /// Structured JSON — suitable for programmatic processing.
  json,

  /// Human-readable Markdown table — suitable for sharing in issues or Slack.
  markdown,
}

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

  /// Reactive config notifier. Mirrors the active config so UI can rebuild
  /// when settings change without polling.
  static final ValueNotifier<LeakRadarConfig> _configNotifier =
      ValueNotifier<LeakRadarConfig>(
    const LeakRadarConfig(enabled: false),
  );

  /// A [ValueListenable] that emits the current [LeakRadarConfig] whenever
  /// [updateConfig] is called.
  ///
  /// Starts with `LeakRadarConfig(enabled: false)` before [init] completes.
  static ValueListenable<LeakRadarConfig> get configListenable =>
      _configNotifier;

  /// Initialises the leak detector with the given [config].
  ///
  /// Call once from `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  /// Calling again disposes the previous engine before starting a new one.
  /// A no-op when [LeakRadarConfig.enabled] is false or in release builds.
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
      _configNotifier.value = config;
    }, fallback: null, logger: _logger);
  }

  /// Test seam: install a pre-built engine (e.g. with a FakeHeapProbe).
  @visibleForTesting
  static Future<void> debugInstall(LeakEngine engine) async {
    await dispose();
    await engine.start();
    _engine = engine;
  }

  /// Triggers a heap scan and returns the resulting [LeakReport].
  ///
  /// [trigger] is a free-form label stored in the report (e.g. `'manual'`,
  /// `'navigation'`). Returns a report with empty findings and
  /// [LeakRadarStatus.disabled] when the engine is not running. Never throws.
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

  /// Registers [object] for precise lifecycle tracking using a `WeakReference`
  /// and `Finalizer`.
  ///
  /// [tag] is a label used in [LeakFinding.tag] to identify the tracked type.
  /// The object will be reported as leaked if it is not GCed within
  /// [LeakRadarConfig.gcCyclesForPreciseLeak] GC cycles after
  /// [markDisposed] is called (or if [markDisposed] is never called).
  /// A no-op when the engine is not running.
  static void track(Object object, {required String tag}) =>
      runSafely<void>(() => _engine?.track(object, tag: tag), fallback: null, logger: _logger);

  /// Resets all accumulated leak state visible in the UI.
  ///
  /// Clears the engine's precise registry, snapshot history, and latest
  /// report, then emits an empty [LeakReport] on [reports] so the UI updates.
  /// A no-op when the engine is not running. Never throws.
  static void clearLeaks() =>
      runSafely<void>(
        () => _engine?.clearLeaks(),
        fallback: null,
        logger: _logger,
      );

  /// Notifies the engine that [object] has been intentionally disposed.
  ///
  /// After this call the engine expects the object to be GCed within
  /// [LeakRadarConfig.disposalGrace] + a few GC cycles. A no-op when the
  /// engine is not running or the object was never [track]ed.
  static void markDisposed(Object object) =>
      runSafely<void>(() => _engine?.markDisposed(object), fallback: null, logger: _logger);

  /// Stream of [LeakReport]s emitted after each scan completes.
  ///
  /// Emits an empty stream when the engine is not running.
  static Stream<LeakReport> get reports =>
      runSafely(() => _engine?.reports ?? const Stream<LeakReport>.empty(), fallback: const Stream<LeakReport>.empty(), logger: _logger);

  /// The most recent [LeakReport], or null if no scan has run yet.
  static LeakReport? get latest =>
      runSafely(() => _engine?.latest, fallback: null, logger: _logger);

  /// Current runtime status of the detector.
  ///
  /// Returns [LeakRadarStatus.disabled] when the engine is not running.
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
  /// engine is disabled, in release, or `showOverlay` is false.
  ///
  /// Any internal error is swallowed — [child] is returned as the fallback so
  /// the host app is never affected.
  static Widget overlay({required Widget child}) {
    final showOverlay = _configNotifier.value.showOverlay && _showOverlay;
    if (!kEngineEnabled || _engine == null || !showOverlay) return child;
    return runSafely(
      () => LeakRadarOverlay(show: true, child: child),
      fallback: child,
      logger: _logger,
    );
  }

  /// Applies [config] to the running engine.
  ///
  /// Reconfigures auto-scan triggers and updates [configListenable]. No-op
  /// when the engine is not running. Never throws.
  static void updateConfig(LeakRadarConfig config) {
    runSafely<void>(() {
      _engine?.updateConfig(config);
      _showOverlay = config.showOverlay;
      _configNotifier.value = config;
    }, fallback: null, logger: _logger);
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

  /// Writes a binary heap snapshot to a file and returns the absolute path.
  ///
  /// The snapshot is written using `dart:developer`'s
  /// [NativeRuntime.writeHeapSnapshotToFile] — no VM-service connection is
  /// required. The file is named `leak_radar_heap_<timestamp>.data` and can
  /// be opened with Flutter DevTools (Memory › Import) or with the repository's
  /// standalone heap analyser.
  ///
  /// Returns `null` when:
  /// - the engine is disabled or not initialised,
  /// - the platform does not support heap snapshots (product mode, web,
  ///   non-standalone VM),
  /// - any other error occurs (always swallowed — never throws into the host).
  ///
  /// [directory] overrides the destination; it defaults to
  /// [Directory.systemTemp] when omitted.
  static Future<String?> captureHeapSnapshotToFile({Directory? directory}) {
    if (!kEngineEnabled || _engine == null) return Future.value(null);
    return runSafelyAsync<String?>(
      () => writeHeapSnapshotFile(directory: directory),
      fallback: null,
      logger: _logger,
    );
  }

  /// Stops the engine and releases all resources.
  ///
  /// Safe to call multiple times. [init] can be called again after [dispose]
  /// to re-start with a different [LeakRadarConfig].
  static Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _configNotifier.value = const LeakRadarConfig(enabled: false);
    _showOverlay = true;
    if (engine != null) {
      await runSafelyAsync(
        () => engine.stop(),
        fallback: null,
        logger: _logger,
      );
    }
  }
}
