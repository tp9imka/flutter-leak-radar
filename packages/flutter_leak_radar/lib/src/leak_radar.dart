// lib/src/leak_radar.dart
import 'package:meta/meta.dart';

import 'analysis/leak_analyzer.dart';
import 'analysis/sample_history.dart';
import 'config/leak_radar_config.dart';
import 'engine/heap_probe.dart';
import 'engine/leak_engine.dart';
import 'engine/vm_heap_probe.dart';
import 'model/leak_kind.dart';
import 'model/leak_report.dart';
import 'precise/leak_object_registry.dart';
import 'util/build_mode.dart';
import 'util/rate_limited_logger.dart';
import 'util/safe.dart';

/// On-device leak detector. Static facade; every method is a no-op in release
/// or when disabled, and never throws into the host.
abstract final class LeakRadar {
  static LeakEngine? _engine;
  static RateLimitedLogger _logger = RateLimitedLogger();

  static Future<void> init(LeakRadarConfig config) async {
    await dispose();
    if (!kEngineEnabled || !config.enabled) {
      _engine = null;
      return;
    }
    await runSafelyAsync<void>(() async {
      _logger = RateLimitedLogger(level: config.logLevel);
      HeapProbe probe = VmHeapProbe(logger: _logger);
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
      );
      await engine.start();
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
    final engine = _engine;
    if (engine == null) {
      return Future.value(LeakReport(
        findings: const [],
        capturedAt: DateTime.now(),
        trigger: trigger,
        status: LeakRadarStatus.disabled,
      ));
    }
    return runSafelyAsync(
      () => engine.scan(trigger: trigger),
      fallback: LeakReport(
        findings: const [],
        capturedAt: DateTime.now(),
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

  static Stream<LeakReport> get reports => _engine?.reports ?? const Stream<LeakReport>.empty();

  static LeakReport? get latest => _engine?.latest;

  static LeakRadarStatus get status => _engine?.status ?? LeakRadarStatus.disabled;

  static Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await runSafelyAsync(() => engine.stop(), fallback: null, logger: _logger);
    }
  }
}
