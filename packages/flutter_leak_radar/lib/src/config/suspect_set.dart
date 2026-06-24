// lib/src/config/suspect_set.dart
import 'package:meta/meta.dart';

import 'leak_rule.dart';

/// An ordered collection of [LeakRule]s that determines which classes the
/// engine monitors for heap growth.
///
/// Use [SuspectSet.defaults] for out-of-the-box coverage of common
/// Flutter/Dart leak-prone types. Layer additional [LeakRule]s via
/// [LeakRadarConfig.rules]; they are merged with higher precedence than the
/// defaults by [merge].
@immutable
final class SuspectSet {
  /// Creates a set from an explicit list of rules.
  const SuspectSet(this.rules);

  /// Creates an empty set — no classes are monitored until rules are added.
  const SuspectSet.empty() : rules = const <LeakRule>[];

  /// Curated defaults for common Flutter/Dart leak-prone types.
  ///
  /// Covers `*State`, `*Screen`, `*Bloc`, `*Cubit`, `*Controller`,
  /// `*Notifier`, `*StreamSubscription`, `*StreamController`, and `*Timer`.
  ///
  /// (Suffix globs rather than exact names so concrete subclasses and the VM's
  /// private implementation classes match — e.g. `*State` catches
  /// `_HomeScreenState`, and `*Timer` catches the `_Timer` instance returned by
  /// `Timer.periodic`, which an exact `Timer` rule would miss.)
  factory SuspectSet.defaults() => const SuspectSet(<LeakRule>[
    LeakRule.growth('*State'),
    LeakRule.growth('*Screen'),
    LeakRule.growth('*Bloc'),
    LeakRule.growth('*Cubit'),
    LeakRule.growth('*Controller'),
    LeakRule.growth('*Notifier'),
    LeakRule.growth('*StreamSubscription'),
    LeakRule.growth('*StreamController'),
    LeakRule.growth('*Timer'),
  ]);

  /// The ordered list of rules in this set.
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
