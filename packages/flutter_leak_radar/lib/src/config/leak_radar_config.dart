// lib/src/config/leak_radar_config.dart
import 'package:flutter/foundation.dart';

import '../model/leak_kind.dart';
import '../util/rate_limited_logger.dart';
import 'leak_rule.dart';
import 'suspect_set.dart';

/// Controls when the engine triggers automatic scans.
///
/// Pass to [LeakRadarConfig] or [LeakRadarConfig.standard]. Both [onNavigation]
/// and [period] can be active simultaneously.
@immutable
final class AutoScan {
  const AutoScan({
    this.onNavigation = false,
    this.period,
    this.navigationDebounce = const Duration(milliseconds: 500),
  });

  /// Trigger a scan after each navigation pop, debounced by [navigationDebounce].
  ///
  /// Requires [LeakRadar.navigatorObserver] to be added to
  /// [MaterialApp.navigatorObservers].
  final bool onNavigation;

  /// Trigger periodic scans at this interval. Null disables periodic scanning.
  final Duration? period;

  /// How long to wait after the last `didPop` before firing the navigation scan.
  ///
  /// Coalesces rapid back-navigations. Defaults to 500 ms.
  final Duration navigationDebounce;

  bool get hasPeriodic => period != null;

  AutoScan copyWith({
    bool? onNavigation,
    Duration? period,
    Duration? navigationDebounce,
  }) => AutoScan(
    onNavigation: onNavigation ?? this.onNavigation,
    period: period ?? this.period,
    navigationDebounce: navigationDebounce ?? this.navigationDebounce,
  );

  @override
  bool operator ==(Object other) =>
      other is AutoScan &&
      other.onNavigation == onNavigation &&
      other.period == period &&
      other.navigationDebounce == navigationDebounce;

  @override
  int get hashCode => Object.hash(onNavigation, period, navigationDebounce);
}

/// Configuration for [LeakRadar.init].
///
/// Use [LeakRadarConfig.standard] for typical wiring — it enables the detector
/// only in debug and profile builds (`kDebugMode || kProfileMode`) and applies
/// [SuspectSet.defaults] out of the box.
@immutable
final class LeakRadarConfig {
  const LeakRadarConfig({
    this.enabled = true,
    this.autoScan = const AutoScan(),
    this.suspects = const SuspectSet.empty(),
    this.rules = const <LeakRule>[],
    this.maxSnapshots = 20,
    this.gcCyclesForPreciseLeak = 3,
    this.disposalGrace = const Duration(seconds: 2),
    this.maxRetainingPathRequests = 5,
    this.logLevel = LeakLogLevel.warning,
    this.showOverlay = true,
    this.reportThreshold = LeakSeverity.info,
    this.preciseTracking = true,
  });

  /// Recommended constructor for production apps.
  ///
  /// Sets [enabled] to `kDebugMode || kProfileMode`, uses
  /// [SuspectSet.defaults], and applies [rules] on top. [gcCyclesForPreciseLeak]
  /// and [disposalGrace] tune how quickly [LeakRadar.markDisposed] objects are
  /// reported; the production defaults trade latency for fewer false positives.
  factory LeakRadarConfig.standard({
    AutoScan autoScan = const AutoScan(),
    List<LeakRule> rules = const <LeakRule>[],
    SuspectSet? suspects,
    int maxSnapshots = 20,
    int gcCyclesForPreciseLeak = 3,
    Duration disposalGrace = const Duration(seconds: 2),
  }) => LeakRadarConfig(
    enabled: kDebugMode || kProfileMode,
    autoScan: autoScan,
    suspects: suspects ?? SuspectSet.defaults(),
    rules: rules,
    maxSnapshots: maxSnapshots,
    gcCyclesForPreciseLeak: gcCyclesForPreciseLeak,
    disposalGrace: disposalGrace,
  );

  /// Master on/off switch. When false the engine is never started and every
  /// [LeakRadar] call is a no-op.
  final bool enabled;

  /// Automatic scan scheduling settings.
  final AutoScan autoScan;

  /// Which class-name patterns the engine monitors for heap growth.
  final SuspectSet suspects;

  /// Extra rules layered on top of [suspects].
  ///
  /// Rules appended here take precedence over [suspects] because they are
  /// evaluated later by [SuspectSet.merge].
  final List<LeakRule> rules;

  /// Rolling history depth for growth analysis. Higher values give more
  /// accurate trend detection at the cost of memory.
  final int maxSnapshots;

  /// Number of GC cycles a tracked object must survive after disposal before
  /// it is reported as a precise leak.
  final int gcCyclesForPreciseLeak;

  /// Time after [LeakRadar.markDisposed] before the object must be GCed.
  final Duration disposalGrace;

  /// Maximum number of retaining-path fetches per scan. Capped to limit VM
  /// service overhead on large heaps.
  final int maxRetainingPathRequests;

  /// Verbosity of internal engine log output.
  final LeakLogLevel logLevel;

  /// Whether [LeakRadar.overlay] should wrap the child in a [LeakRadarOverlay].
  /// Defaults to `true`. Has no effect when the engine is disabled or in release.
  final bool showOverlay;

  /// Minimum severity a finding must meet to appear in reports and the UI.
  ///
  /// Findings below this threshold are still detected internally but are
  /// filtered before emission. Defaults to [LeakSeverity.info] (show all).
  final LeakSeverity reportThreshold;

  /// Whether [LeakRadar.track] and [LeakRadar.markDisposed] are honoured.
  ///
  /// When false, precise opt-in tracking calls are no-ops and the registry
  /// is cleared. Defaults to `true`.
  final bool preciseTracking;

  LeakRadarConfig copyWith({
    bool? enabled,
    AutoScan? autoScan,
    SuspectSet? suspects,
    List<LeakRule>? rules,
    int? maxSnapshots,
    int? gcCyclesForPreciseLeak,
    Duration? disposalGrace,
    int? maxRetainingPathRequests,
    LeakLogLevel? logLevel,
    bool? showOverlay,
    LeakSeverity? reportThreshold,
    bool? preciseTracking,
  }) => LeakRadarConfig(
    enabled: enabled ?? this.enabled,
    autoScan: autoScan ?? this.autoScan,
    suspects: suspects ?? this.suspects,
    rules: rules ?? this.rules,
    maxSnapshots: maxSnapshots ?? this.maxSnapshots,
    gcCyclesForPreciseLeak:
        gcCyclesForPreciseLeak ?? this.gcCyclesForPreciseLeak,
    disposalGrace: disposalGrace ?? this.disposalGrace,
    maxRetainingPathRequests:
        maxRetainingPathRequests ?? this.maxRetainingPathRequests,
    logLevel: logLevel ?? this.logLevel,
    showOverlay: showOverlay ?? this.showOverlay,
    reportThreshold: reportThreshold ?? this.reportThreshold,
    preciseTracking: preciseTracking ?? this.preciseTracking,
  );

  @override
  bool operator ==(Object other) =>
      other is LeakRadarConfig &&
      other.enabled == enabled &&
      other.autoScan == autoScan &&
      other.suspects == suspects &&
      listEquals(other.rules, rules) &&
      other.maxSnapshots == maxSnapshots &&
      other.gcCyclesForPreciseLeak == gcCyclesForPreciseLeak &&
      other.disposalGrace == disposalGrace &&
      other.maxRetainingPathRequests == maxRetainingPathRequests &&
      other.logLevel == logLevel &&
      other.showOverlay == showOverlay &&
      other.reportThreshold == reportThreshold &&
      other.preciseTracking == preciseTracking;

  @override
  int get hashCode => Object.hash(
    enabled,
    autoScan,
    suspects,
    Object.hashAll(rules),
    maxSnapshots,
    gcCyclesForPreciseLeak,
    disposalGrace,
    maxRetainingPathRequests,
    logLevel,
    showOverlay,
    reportThreshold,
    preciseTracking,
  );
}
