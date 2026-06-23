// lib/src/config/leak_radar_config.dart
import 'package:flutter/foundation.dart';

import '../util/rate_limited_logger.dart';
import 'leak_rule.dart';
import 'suspect_set.dart';

@immutable
final class AutoScan {
  const AutoScan({
    this.onNavigation = false,
    this.period,
    this.navigationDebounce = const Duration(milliseconds: 500),
  });

  final bool onNavigation;
  final Duration? period;
  final Duration navigationDebounce;

  bool get hasPeriodic => period != null;

  AutoScan copyWith({
    bool? onNavigation,
    Duration? period,
    Duration? navigationDebounce,
  }) =>
      AutoScan(
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
  });

  /// Typical wiring: enabled only in debug/profile, defaults suspects.
  factory LeakRadarConfig.standard({
    AutoScan autoScan = const AutoScan(),
    List<LeakRule> rules = const <LeakRule>[],
    SuspectSet? suspects,
    int maxSnapshots = 20,
  }) =>
      LeakRadarConfig(
        enabled: kDebugMode || kProfileMode,
        autoScan: autoScan,
        suspects: suspects ?? SuspectSet.defaults(),
        rules: rules,
        maxSnapshots: maxSnapshots,
      );

  final bool enabled;
  final AutoScan autoScan;
  final SuspectSet suspects;
  final List<LeakRule> rules;
  final int maxSnapshots;
  final int gcCyclesForPreciseLeak;
  final Duration disposalGrace;
  final int maxRetainingPathRequests;
  final LeakLogLevel logLevel;

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
  }) =>
      LeakRadarConfig(
        enabled: enabled ?? this.enabled,
        autoScan: autoScan ?? this.autoScan,
        suspects: suspects ?? this.suspects,
        rules: rules ?? this.rules,
        maxSnapshots: maxSnapshots ?? this.maxSnapshots,
        gcCyclesForPreciseLeak: gcCyclesForPreciseLeak ?? this.gcCyclesForPreciseLeak,
        disposalGrace: disposalGrace ?? this.disposalGrace,
        maxRetainingPathRequests: maxRetainingPathRequests ?? this.maxRetainingPathRequests,
        logLevel: logLevel ?? this.logLevel,
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
      other.logLevel == logLevel;

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
      );
}
