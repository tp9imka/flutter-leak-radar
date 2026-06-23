// lib/src/config/leak_rule.dart
import 'package:meta/meta.dart';

import '../model/leak_kind.dart';

/// Internal detection strategy for a [LeakRule].
enum LeakDetectionMode { growth, maxLive, ignore }

/// A rule that tells the engine how to handle classes whose names match [pattern].
///
/// Create rules with the named constructors:
/// - [LeakRule.growth] — flag if the instance count grows across snapshots.
/// - [LeakRule.maxLive] — flag if the live count exceeds a fixed ceiling.
/// - [LeakRule.ignore] — never flag matching classes (suppresses defaults).
///
/// Patterns use simple glob matching: `*X` ends-with, `X*` starts-with,
/// `*X*` contains, bare `X` is an exact match.
@immutable
final class LeakRule {
  const LeakRule._({
    required this.pattern,
    required this.mode,
    this.maxLive,
    this.minGrowth = 1,
    this.severityHint,
  });

  /// Flag classes whose names match [pattern] when their instance count grows
  /// by at least [minGrowth] across the rolling snapshot window.
  const factory LeakRule.growth(
    String pattern, {
    int minGrowth,
    LeakSeverity? severityHint,
  }) = _GrowthRule;

  /// Flag classes whose names match [pattern] when more than [max] instances
  /// are live at scan time.
  const factory LeakRule.maxLive(
    String pattern,
    int max, {
    LeakSeverity? severityHint,
  }) = _MaxLiveRule;

  /// Suppress all findings for classes whose names match [pattern].
  ///
  /// Ignore rules take the highest precedence regardless of position in the
  /// list — they override both [growth] and [maxLive] rules for the same class.
  const factory LeakRule.ignore(String pattern) = _IgnoreRule;

  /// Glob pattern matched against the simple (unqualified) class name.
  final String pattern;

  /// Detection mode selected by the factory constructor used.
  final LeakDetectionMode mode;

  /// Live-count ceiling for [LeakDetectionMode.maxLive] rules.
  final int? maxLive;

  /// Minimum growth threshold for [LeakDetectionMode.growth] rules.
  final int minGrowth;

  /// Optional severity override; defaults to engine heuristics when null.
  final LeakSeverity? severityHint;

  /// Glob match against the simple class name.
  ///
  /// `*X` — ends with X; `X*` — starts with X;
  /// `*X*` — contains X; otherwise exact match.
  bool matches(String className) {
    final p = pattern;
    final star = p.startsWith('*');
    final starEnd = p.endsWith('*');
    if (star && starEnd) {
      return className.contains(p.substring(1, p.length - 1));
    }
    if (star) return className.endsWith(p.substring(1));
    if (starEnd) return className.startsWith(p.substring(0, p.length - 1));
    return className == p;
  }

  @override
  bool operator ==(Object other) =>
      other is LeakRule &&
      other.pattern == pattern &&
      other.mode == mode &&
      other.maxLive == maxLive &&
      other.minGrowth == minGrowth &&
      other.severityHint == severityHint;

  @override
  int get hashCode =>
      Object.hash(pattern, mode, maxLive, minGrowth, severityHint);
}

final class _GrowthRule extends LeakRule {
  const _GrowthRule(
    String pattern, {
    super.minGrowth = 1,
    super.severityHint,
  }) : super._(pattern: pattern, mode: LeakDetectionMode.growth);
}

final class _MaxLiveRule extends LeakRule {
  const _MaxLiveRule(
    String pattern,
    int max, {
    super.severityHint,
  }) : super._(
          pattern: pattern,
          mode: LeakDetectionMode.maxLive,
          maxLive: max,
        );
}

final class _IgnoreRule extends LeakRule {
  const _IgnoreRule(String pattern)
      : super._(pattern: pattern, mode: LeakDetectionMode.ignore);
}
