// lib/src/config/leak_radar_config.dart
import 'package:flutter/foundation.dart';

import '../util/rate_limited_logger.dart';
import 'leak_rule.dart';
import 'suspect_set.dart';

@immutable
final class LeakRadarConfig {
  const LeakRadarConfig({
    this.enabled = true,
    this.suspects = const SuspectSet.empty(),
    this.rules = const <LeakRule>[],
    this.maxSnapshots = 20,
    this.gcCyclesForPreciseLeak = 3,
    this.disposalGrace = const Duration(seconds: 2),
    this.logLevel = LeakLogLevel.warning,
  });

  /// Typical wiring: enabled only in debug/profile, defaults suspects.
  factory LeakRadarConfig.standard({
    List<LeakRule> rules = const <LeakRule>[],
    SuspectSet? suspects,
    int maxSnapshots = 20,
  }) =>
      LeakRadarConfig(
        enabled: kDebugMode || kProfileMode,
        suspects: suspects ?? SuspectSet.defaults(),
        rules: rules,
        maxSnapshots: maxSnapshots,
      );

  final bool enabled;
  final SuspectSet suspects;
  final List<LeakRule> rules;
  final int maxSnapshots;
  final int gcCyclesForPreciseLeak;
  final Duration disposalGrace;
  final LeakLogLevel logLevel;

  LeakRadarConfig copyWith({
    bool? enabled,
    SuspectSet? suspects,
    List<LeakRule>? rules,
    int? maxSnapshots,
    int? gcCyclesForPreciseLeak,
    Duration? disposalGrace,
    LeakLogLevel? logLevel,
  }) =>
      LeakRadarConfig(
        enabled: enabled ?? this.enabled,
        suspects: suspects ?? this.suspects,
        rules: rules ?? this.rules,
        maxSnapshots: maxSnapshots ?? this.maxSnapshots,
        gcCyclesForPreciseLeak: gcCyclesForPreciseLeak ?? this.gcCyclesForPreciseLeak,
        disposalGrace: disposalGrace ?? this.disposalGrace,
        logLevel: logLevel ?? this.logLevel,
      );

  @override
  bool operator ==(Object other) =>
      other is LeakRadarConfig &&
      other.enabled == enabled &&
      other.suspects == suspects &&
      listEquals(other.rules, rules) &&
      other.maxSnapshots == maxSnapshots &&
      other.gcCyclesForPreciseLeak == gcCyclesForPreciseLeak &&
      other.disposalGrace == disposalGrace &&
      other.logLevel == logLevel;

  @override
  int get hashCode => Object.hash(enabled, suspects, Object.hashAll(rules), maxSnapshots, gcCyclesForPreciseLeak, disposalGrace, logLevel);
}
