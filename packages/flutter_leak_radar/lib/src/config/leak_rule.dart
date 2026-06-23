// lib/src/config/leak_rule.dart
import 'package:meta/meta.dart';

import '../model/leak_kind.dart';

enum LeakDetectionMode { growth, maxLive, ignore }

@immutable
final class LeakRule {
  const LeakRule._({
    required this.pattern,
    required this.mode,
    this.maxLive,
    this.minGrowth = 1,
    this.severityHint,
  });

  const factory LeakRule.growth(
    String pattern, {
    int minGrowth,
    LeakSeverity? severityHint,
  }) = _GrowthRule;

  const factory LeakRule.maxLive(
    String pattern,
    int max, {
    LeakSeverity? severityHint,
  }) = _MaxLiveRule;

  const factory LeakRule.ignore(String pattern) = _IgnoreRule;

  final String pattern;
  final LeakDetectionMode mode;
  final int? maxLive;
  final int minGrowth;
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
