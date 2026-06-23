// test/config/leak_radar_config_test.dart
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeakRadarConfig equality', () {
    const ruleA = LeakRule.maxLive('A', 1);

    test('configs differing only in rules are NOT equal', () {
      const withRule = LeakRadarConfig(rules: [ruleA]);
      const withoutRule = LeakRadarConfig(rules: []);
      expect(withRule == withoutRule, isFalse);
    });

    test('configs differing only in rules have different hashCodes', () {
      const withRule = LeakRadarConfig(rules: [ruleA]);
      const withoutRule = LeakRadarConfig(rules: []);
      expect(withRule.hashCode == withoutRule.hashCode, isFalse);
    });

    test('two fully-identical configs are equal with equal hashCodes', () {
      const a = LeakRadarConfig(rules: [ruleA]);
      const b = LeakRadarConfig(rules: [ruleA]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith(rules: ...) produces a config that differs by rules', () {
      const base = LeakRadarConfig(rules: []);
      final changed = base.copyWith(rules: [ruleA]);
      expect(base == changed, isFalse);
      expect(base.hashCode == changed.hashCode, isFalse);
    });
  });
}
