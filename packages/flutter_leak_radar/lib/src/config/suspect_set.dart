// lib/src/config/suspect_set.dart
import 'package:meta/meta.dart';

import 'leak_rule.dart';

@immutable
final class SuspectSet {
  const SuspectSet(this.rules);
  const SuspectSet.empty() : rules = const <LeakRule>[];

  /// Curated defaults for common Flutter/Dart leak-prone types. (`*State`
  /// rather than `State` so concrete State subclasses like `_HomeScreenState`
  /// match — refines the spec's `State` entry.)
  factory SuspectSet.defaults() => const SuspectSet(<LeakRule>[
        LeakRule.growth('*State'),
        LeakRule.growth('*Screen'),
        LeakRule.growth('*Bloc'),
        LeakRule.growth('*Cubit'),
        LeakRule.growth('*Controller'),
        LeakRule.growth('*Notifier'),
        LeakRule.growth('*StreamSubscription'),
        LeakRule.growth('*StreamController'),
        LeakRule.growth('Timer'),
      ]);

  final List<LeakRule> rules;

  /// Returns a new set with [extra] layered after the existing rules.
  ///
  /// Precedence in [ruleFor]: ignore anywhere > last matching extra > defaults.
  SuspectSet merge(List<LeakRule> extra) =>
      SuspectSet(<LeakRule>[...rules, ...extra]);

  /// The effective rule for [className], or null if none applies.
  ///
  /// Ignore rules take highest precedence regardless of position.
  /// Among non-ignore rules, the last match wins (extra rules override
  /// defaults because they are appended by [merge]).
  LeakRule? ruleFor(String className) {
    LeakRule? chosen;
    for (final rule in rules) {
      if (!rule.matches(className)) continue;
      if (rule.mode == LeakDetectionMode.ignore) return rule;
      chosen = rule;
    }
    return chosen;
  }

  @override
  bool operator ==(Object other) =>
      other is SuspectSet && _listEquals(other.rules, rules);

  @override
  int get hashCode => Object.hashAll(rules);
}

bool _listEquals(List<LeakRule> a, List<LeakRule> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
